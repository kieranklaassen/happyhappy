require "test_helper"

class PostAnomalyAlertJobTest < ActiveJob::TestCase
  include SlackStubHelper
  include AnomalyHelper

  setup { Setting.current.update!(slack_channel_id: "C0AGB2RKA6R") }

  test "posts the spike to the Settings channel once, with the customers behind it" do
    stub_slack_post_message
    anomaly = create_anomaly!(product: products(:sparkle), dimension: categories(:billing).id.to_s, expected: 0.2, actual: 8)

    PostAnomalyAlertJob.perform_now(anomaly)
    PostAnomalyAlertJob.perform_now(anomaly.reload)

    post = slack_posts.sole
    assert_equal "C0AGB2RKA6R", post["channel"]
    assert_equal "Sparkle: billing messages spiked", post["text"]
    rendered = post["blocks"].to_json
    assert_includes rendered, "billing messages spiked (8 vs about 0.2 usual, high)"
    assert_includes rendered, "/products/#{products(:sparkle).id}/overview"
    assert_includes rendered, "/items/#{items(:angry_slack).id}"
    assert anomaly.reload.slack_alerted_at?
  end

  test "does nothing without a Settings channel" do
    stub_slack_post_message
    Setting.current.update!(slack_channel_id: nil)
    anomaly = create_anomaly!

    PostAnomalyAlertJob.perform_now(anomaly)

    assert_empty slack_posts
    assert_nil anomaly.reload.slack_alerted_at
  end

  test "only live, all-sources, high-severity bad news is alertable" do
    assert create_anomaly!.slack_alertable?
    assert_not create_anomaly!(severity: "medium").slack_alertable?
    assert_not create_anomaly!(source: sources(:slack_community)).slack_alertable?
    assert_not create_anomaly!(historical: true, status: "ended", ended_at: Time.current).slack_alertable?
    assert_not create_anomaly!(polarity: "positive", severity: nil, highlight: "huge", metric: "mood_share", dimension: "beaming").slack_alertable?
  end
end
