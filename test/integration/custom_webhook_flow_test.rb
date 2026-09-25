require "test_helper"

# Custom inbound webhook end to end: a team member creates a custom source for
# a product, reads its URL and signing secret on the edit page, and the
# product posts signed messages, asking for labels inline with sync mode.
class CustomWebhookFlowTest < ActionDispatch::IntegrationTest
  setup do
    Webhooks::CustomController::SYNC_RATE_LIMIT_STORE.clear
    sign_in_as users(:every_ana)
  end

  test "a signed sync POST to a new custom source returns labels from the classifier and files the item" do
    post sources_path, params: { source: {
      kind: "custom", name: "Spiral in-app feedback", selector: "spiral-in-app", default_product_id: products(:spiral).id
    } }
    source = Source.find_by!(kind: "custom", name: "Spiral in-app feedback")
    assert_redirected_to edit_source_path(source)

    get edit_source_path(source)
    webhook = inertia.props[:webhook]
    url = URI(webhook[:url])
    secret = webhook[:signing_secret]
    assert_equal "/webhooks/custom/#{source.public_token}", url.path

    use_fake_classifier(product: "spiral", category: "bug", sentiment: "complaint", anger: 0.4)
    body = { id: "fb-100", text: "Spiral dropped half my draft when I hit undo.", thread_key: "session-7",
      author: { name: "Rae" } }.to_json
    post "#{url.path}?sync=true", params: body,
      headers: { "Content-Type" => "application/json", Webhooks::Signature::HEADER => Webhooks::Signature.sign(secret, body) }

    assert_response :ok
    labels = response.parsed_body.fetch("labels")
    assert_equal "classified", response.parsed_body["classification"]
    assert_equal "spiral", labels.dig("product", "value")
    assert_equal "complaint", labels.dig("sentiment", "value")
    assert_in_delta 0.4, labels.dig("anger", "probability")

    item = Item.find(response.parsed_body["item_id"])
    assert_equal source, item.source
    assert_equal products(:spiral), item.product
    assert_equal %w[arrived classified], item.events.map(&:kind)
    get items_path(product: "spiral", source_kind: "custom")
    assert_equal [ item.id ], inertia.props[:items].map { |row| row[:id] }
  end

  test "a POST signed with a rotated-out secret is refused and stores nothing" do
    source = sources(:cora_app_webhook)
    old_secret = source.signing_secret
    patch rotate_secret_source_path(source)

    body = { text: "Cora keeps crashing" }.to_json
    assert_no_difference -> { Message.count } do
      post "/webhooks/custom/#{source.public_token}", params: body,
        headers: { "Content-Type" => "application/json", Webhooks::Signature::HEADER => Webhooks::Signature.sign(old_secret, body) }
    end
    assert_response :unauthorized
  end
end
