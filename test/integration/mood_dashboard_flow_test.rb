require "test_helper"

# Mood dashboard end to end: a signed Slack event is ingested and classified
# (fake classifier), the customer shows up on the home page as a character in
# the classified product with the matching mood, and open dashboards get a
# MoodChannel ping when the classification lands.
class MoodDashboardFlowTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper
  include SlackEventsHelper
  include SlackStubHelper

  setup do
    stub_slack_users_info
    stub_slack_permalink
    stub_slack_post_message
    sign_in_as users(:every_ana)
  end

  test "a classified Slack message appears on the dashboard in its product with its mood and pings MoodChannel" do
    ts = "#{Time.current.to_i}.000400"
    perform_enqueued_jobs(only: SlackEventJob) do
      post_slack_event slack_payload("message_event", event: { ts: ts, event_ts: ts })
    end
    item = Item.find_by!(source_kind: "slack", thread_key: "C0COMMUNITY:#{ts}")

    use_fake_classifier(product: "spiral", sentiment: "complaint", anger: 0.9)
    assert_broadcasts(MoodChannel::STREAM, 1) do
      perform_enqueued_jobs(only: ClassifyMessageJob)
    end
    assert_equal({ "backfill" => false }, ActiveSupport::JSON.decode(broadcasts(MoodChannel::STREAM).last).except("changed_at"))

    get root_path
    assert_response :success
    assert_inertia_component "home/index"
    spiral = inertia.props[:scene].find { |group| group.dig(:product, :slug) == "spiral" }
    character = spiral[:characters].find { |entry| entry[:item_id] == item.id }
    assert_equal "furious", character[:mood]
    assert_equal "complaint", character[:sentiment]
    assert_equal "slack", character[:source_kind]
    assert_includes character[:excerpt], "Cora archived my whole inbox"
    assert_not(inertia.props[:scene].any? do |group|
      group.dig(:product, :slug) != "spiral" && group[:characters].any? { |entry| entry[:item_id] == item.id }
    end)
  end

  test "an agent claiming and handling the item pings MoodChannel each time and the character shows as mended" do
    ts = "#{Time.current.to_i}.000500"
    use_fake_classifier(product: "cora", sentiment: "complaint", anger: 0.6)
    perform_enqueued_jobs do
      post_slack_event slack_payload("message_event", event: { ts: ts, event_ts: ts })
    end
    item = Item.find_by!(thread_key: "C0COMMUNITY:#{ts}")
    assert_broadcasts(MoodChannel::STREAM, 1) { Agents::Claim.call(agent: agents(:cursor), item: item) }

    assert_broadcasts(MoodChannel::STREAM, 1) do
      Agents::Report.call(agent: agents(:cursor), item: item.reload, summary: "Restored the inbox.", status: "handled")
    end

    get root_path(product: "cora")
    character = inertia.props[:scene].sole[:characters].find { |entry| entry[:item_id] == item.id }
    assert_equal "grumpy", character[:mood]
    assert_equal "handled", character[:status]
    assert character[:mended]
  end

  private

  def post_slack_event(payload)
    body = payload.to_json
    with_slack_env do
      post webhooks_slack_events_path, params: body, headers: slack_signature_headers(body)
    end
  end
end
