require "test_helper"

class Webhooks::CustomControllerTest < ActionDispatch::IntegrationTest
  SECRET = "hhsec_cora-app-test-secret"

  setup do
    @source = sources(:cora_app_webhook)
    Webhooks::CustomController::SYNC_RATE_LIMIT_STORE.clear
  end

  teardown { Connectors::Custom.sync_timeout = nil }

  test "a signed message creates an item on the source's product and answers 202" do
    body = { id: "fb-1", text: "Cora keeps archiving my newsletters", author: { name: "Dana", email: "dana@example.com" },
      thread_key: "ticket-9", permalink: "https://cora.computer/feedback/1", metadata: { plan: "pro" } }.to_json

    assert_difference -> { Item.count } => 1, -> { Message.count } => 1 do
      assert_enqueued_with(job: ClassifyMessageJob) { deliver body }
    end

    assert_response :accepted
    item = Item.find_by!(source_kind: "custom", thread_key: "source-#{@source.id}:ticket-9")
    assert_equal products(:cora), item.product
    assert_equal @source, item.source
    assert_equal "dana@example.com", item.author_email
    assert_equal({ "plan" => "pro" }, item.messages.sole.raw_payload["metadata"])
    assert_equal({ "item_id" => item.id, "message_id" => item.messages.sole.id, "duplicate" => false,
      "classification" => "pending", "item_status" => "new", "labels" => nil }, response.parsed_body)
  end

  test "sync mode with the fake classifier answers 200 with labels and probabilities" do
    use_fake_classifier(product: "cora", category: "bug", sentiment: "complaint", anger: 0.85)

    deliver({ text: "Cora lost every email from today" }.to_json, sync: true)

    assert_response :ok
    body = response.parsed_body
    assert_equal "classified", body["classification"]
    assert_equal "cora", body.dig("labels", "product", "value")
    assert_in_delta 0.9, body.dig("labels", "product", "probability")
    assert_equal "complaint", body.dig("labels", "sentiment", "value")
    assert_in_delta 0.8, body.dig("labels", "sentiment", "probabilities", "complaint")
    assert_in_delta 0.95, body.dig("labels", "relevant", "probability")
    assert_in_delta 0.85, body.dig("labels", "anger", "probability")
    assert Message.find(body["message_id"]).classified?
    assert_equal "complaint", Item.find(body["item_id"]).sentiment
  end

  test "a sync request keeps a delayed classification job as the fallback" do
    use_fake_classifier

    freeze_time do
      assert_enqueued_with(job: ClassifyMessageJob, at: Connectors::Custom::SYNC_FALLBACK_DELAY.from_now) do
        deliver({ text: "Love the new digest" }.to_json, sync: true)
      end
    end
  end

  test "a classifier timeout in sync mode answers 200 with a pending status and keeps the job queued" do
    use_fake_classifier(->(_message) { sleep 1 })
    Connectors::Custom.sync_timeout = 0.05

    assert_enqueued_with(job: ClassifyMessageJob) do
      deliver({ text: "Is anyone there?" }.to_json, sync: true)
    end

    assert_response :ok
    assert_equal "pending", response.parsed_body["classification"]
    assert_nil response.parsed_body["labels"]
    assert_not Message.find(response.parsed_body["message_id"]).classified?
  end

  test "a classifier error in sync mode answers 200 with a pending status" do
    use_fake_classifier.fail_with(RubyLLM::ServerError.new("boom"))

    deliver({ text: "Hello" }.to_json, sync: true)

    assert_response :ok
    assert_equal "pending", response.parsed_body["classification"]
  end

  test "an error while applying labels in sync mode answers 200 with a pending status" do
    use_fake_classifier
    original = Classification::Apply.method(:call)
    Classification::Apply.define_singleton_method(:call) { |**| raise ActiveRecord::RecordInvalid }
    begin
      deliver({ text: "Hello" }.to_json, sync: true)
    ensure
      Classification::Apply.define_singleton_method(:call, original)
    end

    assert_response :ok
    assert_equal "pending", response.parsed_body["classification"]
  end

  test "answers a rolled back apply cannot store in sync mode answer 200 with a pending status" do
    use_fake_classifier(anger: 2)

    deliver({ text: "Hello" }.to_json, sync: true)

    assert_response :ok
    assert_equal "pending", response.parsed_body["classification"]
    assert_not Message.find(response.parsed_body["message_id"]).classified?
  end

  test "a bad signature answers 401 and stores nothing" do
    body = { text: "hi" }.to_json

    assert_no_difference -> { Message.count } do
      deliver body, signature: Webhooks::Signature.sign("wrong-secret", body)
    end

    assert_response :unauthorized
  end

  test "a stale signature answers 401 and stores nothing" do
    body = { text: "hi" }.to_json

    assert_no_difference -> { Message.count } do
      deliver body, signature: Webhooks::Signature.sign(SECRET, body, time: 6.minutes.ago)
    end

    assert_response :unauthorized
  end

  test "a missing signature answers 401" do
    post "/webhooks/custom/#{@source.public_token}", params: { text: "hi" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "an unknown token answers 404" do
    body = { text: "hi" }.to_json

    post "/webhooks/custom/nope", params: body, headers: signed_headers(body)

    assert_response :not_found
  end

  test "a paused source answers 404" do
    @source.update!(status: :paused)

    deliver({ text: "hi" }.to_json)

    assert_response :not_found
  end

  test "a body over 16 KB answers 413" do
    body = { text: "a" * 16.kilobytes }.to_json

    assert_no_difference -> { Message.count } do
      deliver body
    end

    assert_response :content_too_large
  end

  test "the same id twice stores one message" do
    first = { id: "fb-7", text: "Spiral drafts vanish" }.to_json
    again = { id: "fb-7", text: "Spiral drafts vanish", metadata: { retry: 1 } }.to_json

    assert_difference -> { Message.count } => 1 do
      deliver first
      deliver again
    end

    assert response.parsed_body["duplicate"]
  end

  test "without an id, the same body twice stores one message and different bodies make two items" do
    assert_difference -> { Message.count } => 2, -> { Item.count } => 2 do
      deliver({ text: "one" }.to_json)
      deliver({ text: "one" }.to_json)
      deliver({ text: "two" }.to_json)
    end
  end

  test "sync requests over the rate limit answer 429" do
    use_fake_classifier
    limit = Webhooks::CustomController::SYNC_RATE_LIMIT

    limit.times { |n| deliver({ text: "message #{n}" }.to_json, sync: true) }
    assert_response :ok

    assert_no_difference -> { Message.count } do
      deliver({ text: "one too many" }.to_json, sync: true)
    end
    assert_response :too_many_requests

    deliver({ text: "async still flows" }.to_json)
    assert_response :accepted
  end

  test "rotating the secret makes the old secret fail" do
    @source.rotate_signing_secret!
    body = { text: "hi" }.to_json

    deliver body
    assert_response :unauthorized

    deliver body, signature: Webhooks::Signature.sign(@source.signing_secret, body)
    assert_response :accepted
  end

  test "invalid payloads answer 422 with the reason and store nothing" do
    {
      "not json" => "body must be valid JSON",
      "[1, 2]" => "body must be a JSON object",
      { author: "Dana" }.to_json => "text is required",
      { text: "  " }.to_json => "text is required",
      { text: "hi", metadata: "x" }.to_json => "metadata must be an object",
      { text: "hi", author: 5 }.to_json => "author must be a string or an object",
      { text: "hi", occurred_at: "yesterday" }.to_json => "occurred_at must be an ISO 8601 time"
    }.each do |body, error|
      assert_no_difference -> { Message.count } do
        deliver body
      end
      assert_response :unprocessable_content
      assert_equal error, response.parsed_body["error"], body
    end
  end

  test "a string author and occurred_at are kept" do
    deliver({ id: 42, text: "Nice", author: "dana", occurred_at: "2026-09-01T10:00:00Z" }.to_json)

    message = Message.find(response.parsed_body["message_id"])
    assert_equal "42", message.external_id
    assert_equal "source-#{@source.id}:42", message.item.thread_key
    assert_equal "dana", message.item.author_name
    assert_equal Time.utc(2026, 9, 1, 10), message.occurred_at
  end

  private

  def deliver(body, sync: false, signature: Webhooks::Signature.sign(SECRET, body))
    path = "/webhooks/custom/#{@source.public_token}"
    path += "?sync=true" if sync
    post path, params: body, headers: signed_headers(body, signature: signature)
  end

  def signed_headers(body, signature: Webhooks::Signature.sign(SECRET, body))
    { "Content-Type" => "application/json", Webhooks::Signature::HEADER => signature }
  end
end
