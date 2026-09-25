require "test_helper"

# F1 end to end: a provider webhook goes through ingest, the classify job (fake
# classifier), the item.classified subscriber, and the escalation job, with
# every Slack API call stubbed.
class EscalationFlowTest < ActionDispatch::IntegrationTest
  include SlackEventsHelper
  include SlackStubHelper
  include IntercomPayloads

  INTERCOM_SECRET = "intercom-test-client-secret"

  setup do
    stub_slack_users_info
    stub_slack_permalink
    stub_slack_post_message
  end

  test "covers F1: a signed Slack event with an angry message produces an item, a classification, and one Slack escalation" do
    fake = use_fake_classifier(product: "cora", category: "bug", sentiment: "complaint", anger: 0.9)
    ts = "#{Time.current.to_i}.000200"

    perform_enqueued_jobs do
      post_slack_event slack_payload("message_event", event: { ts: ts, event_ts: ts })
    end

    assert_response :ok
    item = Item.find_by!(source_kind: "slack", thread_key: "C0COMMUNITY:#{ts}")
    assert_equal [ item.messages.sole ], fake.calls
    assert item.relevant?
    assert item.complaint?
    assert_equal products(:cora), item.product
    assert_in_delta 0.9, item.anger_probability

    escalation = item.escalations.sole
    assert escalation.posted?
    assert_equal SLACK_OK_TS, escalation.slack_message_ts
    post = slack_posts.sole
    assert_equal "C0CORASUPPORT", post["channel"]
    assert_includes post["blocks"].to_json, "Cora archived my whole inbox"
    assert_includes post["blocks"].to_json, "/items/#{item.id}"
    assert_equal %w[arrived classified escalated], item.events.map(&:kind)

    sign_in_as users(:every_ana)
    get item_path(item)
    assert_response :success
    assert_equal "new", inertia.props[:item][:status]
    assert_includes inertia.props[:events].map { |event| event[:kind] }, "escalated"
  end

  test "covers F1: the same Slack event delivered twice still posts one escalation" do
    use_fake_classifier(anger: 0.95)
    ts = "#{Time.current.to_i}.000300"
    payload = slack_payload("message_event", event: { ts: ts, event_ts: ts })

    perform_enqueued_jobs do
      2.times { post_slack_event payload }
    end

    assert_equal 1, Item.find_by!(thread_key: "C0COMMUNITY:#{ts}").messages.count
    assert_equal 1, slack_posts.size
  end

  test "covers AE5: three angry Intercom replies in one conversation post one escalation on one item's timeline" do
    use_fake_classifier(product: "cora", sentiment: "complaint", anger: 0.92)
    now = Time.current.to_i
    created = intercom_created
    created["data"]["item"]["created_at"] = now - 600

    with_intercom_secret do
      perform_enqueued_jobs do
        deliver_intercom created
        %w[r-1 r-2 r-3].each_with_index do |part_id, index|
          deliver_intercom intercom_replied(id: part_id, body: "<p>Still broken #{index}</p>", created_at: now - 300 + index)
          assert_response :ok
        end
      end
    end

    item = Item.find_by!(source_kind: "intercom", thread_key: "215470000000777")
    assert_equal 4, item.messages.count
    assert_equal 1, item.escalations.count
    assert_equal 1, slack_posts.size
    assert_equal "C0CORASUPPORT", slack_posts.sole["channel"]
    arrived = item.events.select(&:arrived?).map { |event| event.data["message_id"] }
    assert_equal item.messages.map(&:id), arrived
  end

  private

  def post_slack_event(payload)
    body = payload.to_json
    with_slack_env do
      post webhooks_slack_events_path, params: body, headers: slack_signature_headers(body)
    end
  end

  def deliver_intercom(payload)
    body = payload.to_json
    post "/webhooks/intercom", params: body, headers: {
      "Content-Type" => "application/json",
      "X-Hub-Signature" => "sha1=#{OpenSSL::HMAC.hexdigest("SHA1", INTERCOM_SECRET, body)}"
    }
  end

  def with_intercom_secret
    previous = ENV["INTERCOM_CLIENT_SECRET"]
    ENV["INTERCOM_CLIENT_SECRET"] = INTERCOM_SECRET
    yield
  ensure
    ENV["INTERCOM_CLIENT_SECRET"] = previous
  end
end
