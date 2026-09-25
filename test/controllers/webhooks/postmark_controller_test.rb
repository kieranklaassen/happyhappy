require "test_helper"

class Webhooks::PostmarkControllerTest < ActionDispatch::IntegrationTest
  USER = "postmark-test-user"
  PASSWORD = "postmark-test-password"

  setup do
    @previous_env = ENV.to_h.slice("POSTMARK_INBOUND_USER", "POSTMARK_INBOUND_PASSWORD")
    ENV["POSTMARK_INBOUND_USER"] = USER
    ENV["POSTMARK_INBOUND_PASSWORD"] = PASSWORD
  end

  teardown do
    %w[POSTMARK_INBOUND_USER POSTMARK_INBOUND_PASSWORD].each { |key| ENV[key] = @previous_env[key] }
  end

  test "an authenticated payload to a configured address creates an item with the sender as author" do
    assert_difference -> { Item.count } => 1, -> { Message.count } => 1 do
      deliver file_fixture("postmark/inbound_first.json").read
    end

    assert_response :ok
    item = Item.order(:id).last
    assert_equal sources(:support_email), item.source
    assert_equal "dana@example.com", item.author_email
  end

  test "a reply with In-Reply-To and References joins the original item" do
    deliver file_fixture("postmark/inbound_first.json").read

    assert_no_difference -> { Item.count } do
      deliver file_fixture("postmark/inbound_reply.json").read
    end

    assert_response :ok
    assert_equal 2, Item.order(:id).last.messages.count
  end

  test "the same MessageID twice stores one message" do
    deliver file_fixture("postmark/inbound_first.json").read

    assert_no_difference -> { Message.count } do
      deliver file_fixture("postmark/inbound_first.json").read
    end
    assert_response :ok
  end

  test "missing basic auth returns 401 and stores nothing" do
    assert_no_difference -> { Message.count } do
      post postmark_webhook_path, params: file_fixture("postmark/inbound_first.json").read,
        headers: { "CONTENT_TYPE" => "application/json" }
    end

    assert_response :unauthorized
  end

  test "a wrong password returns 401 and stores nothing" do
    assert_no_difference -> { Message.count } do
      deliver file_fixture("postmark/inbound_first.json").read, password: "wrong"
    end

    assert_response :unauthorized
  end

  test "unset credentials refuse every request" do
    ENV["POSTMARK_INBOUND_USER"] = nil
    ENV["POSTMARK_INBOUND_PASSWORD"] = nil

    deliver file_fixture("postmark/inbound_first.json").read, user: "", password: ""

    assert_response :unauthorized
  end

  test "an unknown recipient returns 200 and stores nothing" do
    payload = JSON.parse(file_fixture("postmark/inbound_first.json").read)
    payload["ToFull"] = [ { "Email" => "nobody@example.com", "Name" => "", "MailboxHash" => "" } ]

    assert_no_difference -> { Item.count } do
      deliver payload.to_json
    end

    assert_response :ok
  end

  test "a payload that cannot be ingested returns 422" do
    payload = JSON.parse(file_fixture("postmark/inbound_first.json").read)
    payload.delete("MessageID")

    deliver payload.to_json

    assert_response :unprocessable_content
  end

  test "a body that is not a JSON object returns 400" do
    deliver "not json"
    assert_response :bad_request

    deliver "[]"
    assert_response :bad_request
  end

  test "the app draws no Action Mailbox routes and has no Action Mailbox tables" do
    paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s }

    assert paths.none? { |path| path.include?("action_mailbox") }
    refute Object.const_defined?(:ActionMailbox)
    assert_no_match(/action_mailbox/, Rails.root.join("db/schema.rb").read)
  end

  test "answers once the message is stored, leaving classification to the realtime queue" do
    fake = use_fake_classifier

    assert_enqueued_with(job: ClassifyMessageJob, queue: "realtime") { deliver file_fixture("postmark/inbound_first.json").read }

    assert_response :ok
    assert_empty fake.calls
  end

  private

  def deliver(body, user: USER, password: PASSWORD)
    post postmark_webhook_path, params: body, headers: {
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(user, password)
    }
  end
end
