require "test_helper"

class Escalations::CheckTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SlackStubHelper

  test "covers F1: an item classified with anger 0.85 and a product channel posts one escalation" do
    stub_slack_post_message
    item, message = classified_item(anger: 0.85)

    perform_enqueued_jobs(only: PostEscalationJob) { item.publish_classified(message) }

    escalation = item.escalations.sole
    assert_equal products(:cora), escalation.product
    assert_equal "C0CORASUPPORT", escalation.slack_channel_id
    assert_equal message, escalation.message
    assert escalation.posted?

    post = slack_posts.sole
    assert_equal "C0CORASUPPORT", post["channel"]
    rendered = post["blocks"].to_json
    assert_includes rendered, "Cora ate my drafts again"
    assert_includes rendered, "Cora"
    assert_includes rendered, sources(:discord_spiral).name
    assert_includes rendered, "furious_fan"
    assert_includes rendered, "/items/#{item.id}"
  end

  test "covers AE5: three angry messages in one thread produce one escalation" do
    item, first = classified_item(anger: 0.9)
    later = 2.times.map { |index| add_message(item, anger: 0.95, body: "Still broken #{index}") }

    assert_enqueued_jobs 1, only: PostEscalationJob do
      [ first, *later ].each { |message| item.publish_classified(message) }
    end
    assert_equal 1, item.escalations.count
  end

  test "after the item's status changes a new angry message may escalate again" do
    item, message = classified_item(anger: 0.9)
    item.publish_classified(message)
    item.change_status!(:handled)

    newer = add_message(item, anger: 0.92, body: "It happened again")
    item.publish_classified(newer)

    assert_equal 2, item.escalations.count
    assert_equal newer, item.escalations.order(:created_at).last.message
  end

  test "anger 0.79 under the default 0.8 threshold posts nothing" do
    item, message = classified_item(anger: 0.79)

    assert_no_enqueued_jobs(only: PostEscalationJob) { item.publish_classified(message) }
    assert_empty item.escalations
  end

  test "a product's own threshold overrides the default" do
    item, message = classified_item(anger: 0.75, product: products(:spiral))

    assert_enqueued_jobs(1, only: PostEscalationJob) { item.publish_classified(message) }
    assert_equal "C0SPIRALSUPPORT", item.escalations.sole.slack_channel_id
  end

  test "a product with no Slack channel posts nothing" do
    item, message = classified_item(anger: 0.95, product: products(:sparkle))

    assert_no_enqueued_jobs(only: PostEscalationJob) { item.publish_classified(message) }
    assert_empty item.escalations
  end

  test "an item that is not relevant posts nothing" do
    item, message = classified_item(anger: 0.95, relevant: false)

    item.publish_classified(message)

    assert_empty item.escalations
  end

  test "an angry off-topic reply cannot escalate an item whose relevant anger is low" do
    item, _calm = classified_item(anger: 0.2)
    off_topic = add_message(item, anger: 0.97, body: "This coffee machine is the worst")

    item.publish_classified(off_topic)

    assert_empty item.escalations
  end

  test "a message older than 7 days never escalates" do
    item, message = classified_item(anger: 0.95, occurred_at: 8.days.ago)

    item.publish_classified(message)

    assert_empty item.escalations
  end

  test "a backfilled message never escalates, even when recent and angry" do
    item, message = classified_item(anger: 0.95)
    message.update!(backfilled: true)

    assert_no_enqueued_jobs(only: PostEscalationJob) do
      item.publish_classified(message)
      item.publish_classified
    end
    assert_empty item.escalations
  end

  test "an event without a message judges the customer's latest open message, not the angriest" do
    item, = classified_item(anger: 0.9)
    add_message(item, anger: 0.1, body: "Thanks, that fixed it!")

    assert_no_enqueued_jobs(only: PostEscalationJob) { item.publish_classified }
    assert_empty item.escalations
  end

  test "an event without a message skips team replies when picking the trigger" do
    item, message = classified_item(anger: 0.9)
    add_message(item, anger: 0.95, body: "We are on it, sorry!", author_role: "team")

    item.publish_classified

    assert_equal message, item.escalations.sole.message
  end

  test "a team message never escalates" do
    item, = classified_item(anger: 0.9)
    reply = add_message(item, anger: 0.95, body: "Kieran from Every here: this is unacceptable on our side.",
      author_role: "team")

    assert_no_enqueued_jobs(only: PostEscalationJob) { item.publish_classified(reply) }
    assert_empty item.escalations
  end

  test "the post is enqueued only after the surrounding transaction commits" do
    item, message = classified_item(anger: 0.9)

    assert_enqueued_jobs 1, only: PostEscalationJob do
      ApplicationRecord.transaction do
        item.publish_classified(message)
        assert_no_enqueued_jobs only: PostEscalationJob
      end
    end
  end

  test "reloading code keeps a single item.classified subscriber" do
    listeners = -> { ActiveSupport::Notifications.notifier.listeners_for(Item::CLASSIFIED_EVENT).size }

    assert_no_changes(listeners) { Rails.application.reloader.prepare! }
  end

  private

  def classified_item(anger:, product: products(:cora), relevant: true, occurred_at: 5.minutes.ago)
    item = Item.create!(source: sources(:discord_spiral), thread_key: "thread-#{SecureRandom.hex(4)}",
      author_handle: "furious_fan", permalink: "https://discord.com/channels/1/2/3", product: product,
      sentiment: "complaint", anger_probability: anger, relevant: relevant, last_message_at: occurred_at,
      status_changed_at: occurred_at - 1.minute)
    [ item, add_message(item, anger: anger, occurred_at: occurred_at, body: "Cora ate my drafts again. Unacceptable.") ]
  end

  def add_message(item, anger:, body:, occurred_at: Time.current, author_role: "customer")
    item.messages.create!(source: item.source, external_id: SecureRandom.hex(8), body: body,
      occurred_at: occurred_at, anger_probability: anger, classified_at: Time.current, author_role: author_role)
  end
end
