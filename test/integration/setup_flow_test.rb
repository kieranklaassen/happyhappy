require "test_helper"

# F3 end to end: a team member sets up a product and its Intercom inbox through
# the admin screens, and the next signed Intercom delivery lands on that
# product's feed and alerts that product's Slack channel (stubbed).
class SetupFlowTest < ActionDispatch::IntegrationTest
  include IntercomPayloads
  include SlackStubHelper

  INTERCOM_SECRET = "intercom-test-client-secret"
  TEAM_ID = "7000099"

  setup do
    @previous_secret = ENV["INTERCOM_CLIENT_SECRET"]
    ENV["INTERCOM_CLIENT_SECRET"] = INTERCOM_SECRET
    stub_slack_post_message
    sign_in_as users(:every_ana)
  end

  teardown { ENV["INTERCOM_CLIENT_SECRET"] = @previous_secret }

  test "covers F3: a new product and Intercom source route a signed Intercom webhook to that product" do
    post products_path, params: { product: {
      name: "Monologue", description: "Dictation app.", hint_words: "monologue, dictation",
      slack_channel_id: "C0MONOSUPPORT", digest_hour: "8"
    } }
    assert_redirected_to products_path
    product = Product.find_by!(slug: "monologue")

    post sources_path, params: { source: {
      kind: "intercom", name: "Intercom Monologue inbox", selector: TEAM_ID, default_product_id: product.id
    } }
    assert_redirected_to sources_path
    source = Source.find_by!(kind: "intercom", selector: TEAM_ID)
    assert_equal product, source.default_product

    use_fake_classifier(product: "none", product_probability: 0.2, sentiment: "complaint", anger: 0.9)
    perform_enqueued_jobs do
      deliver_intercom conversation_for_team(TEAM_ID)
    end
    assert_response :ok

    item = Item.find_by!(source_kind: "intercom", thread_key: "215470000000777")
    assert_equal source, item.source
    assert_equal product, item.product
    assert item.relevant?

    get items_path(product: "monologue")
    assert_equal [ item.id ], inertia.props[:items].map { |row| row[:id] }
    assert_equal "Monologue", inertia.props[:items].sole.dig(:product, :name)

    get sources_path
    row = inertia.props[:sources].find { |entry| entry[:id] == source.id }
    assert_not_nil row[:last_message_at]

    assert_equal [ "C0MONOSUPPORT" ], slack_posts.map { |post| post["channel"] }
  end

  test "covers F3: a conversation for a team no source selects is not ingested" do
    assert_no_difference -> { Message.count } do
      deliver_intercom conversation_for_team("7000555")
    end
    assert_response :ok
  end

  private

  def conversation_for_team(team_id)
    intercom_created.tap do |payload|
      payload["data"]["item"]["team_assignee_id"] = team_id
      payload["data"]["item"]["created_at"] = Time.current.to_i
    end
  end

  def deliver_intercom(payload)
    body = payload.to_json
    post "/webhooks/intercom", params: body, headers: {
      "Content-Type" => "application/json",
      "X-Hub-Signature" => "sha1=#{OpenSSL::HMAC.hexdigest("SHA1", INTERCOM_SECRET, body)}"
    }
  end
end
