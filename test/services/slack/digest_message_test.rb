require "test_helper"

class Slack::DigestMessageTest < ActiveSupport::TestCase
  setup do
    @day = Date.current - 5
    @noon = @day.in_time_zone.noon
  end

  test "lists sentiment mix, top categories, standout praise and complaints, and agent-handled counts" do
    worst = add_item(sentiment: "complaint", anger: 0.95, category: categories(:bug), handle: "worst_day", body: "Cora lost every email")
    add_item(sentiment: "complaint", anger: 0.9, category: categories(:bug), handle: "second_worst")
    add_item(sentiment: "complaint", anger: 0.5, category: categories(:bug), handle: "mildly_upset")
    add_item(sentiment: "complaint", anger: 0.3, category: categories(:billing), handle: "calmest_complainer")
    fan = add_item(sentiment: "praise", sentiment_probability: 0.97, category: categories(:praise), handle: "big_fan", body: "Cora saves me an hour a day")
    add_item(sentiment: "praise", sentiment_probability: 0.8, category: categories(:praise), handle: "small_fan")
    add_item(sentiment: "question", category: categories(:onboarding), handle: "curious")
    add_item(sentiment: "complaint", anger: 0.99, relevant: false, handle: "off_topic")
    add_item(sentiment: "complaint", anger: 0.99, product: products(:spiral), handle: "spiral_person")
    add_item(sentiment: "complaint", anger: 0.99, occurred_at: @noon - 2.days, handle: "old_news")

    report(worst, agents(:cursor), "handled")
    report(fan, agents(:baby_agent), "handled")
    report(fan, agents(:baby_agent), "handled")
    report(worst, agents(:cursor), "in_progress")

    payload = Slack::DigestMessage.new(products(:cora), @day).to_h
    rendered = payload[:blocks].map { |block| block.dig(:text, :text) || block[:elements].sole[:text] }.join("\n")

    assert_equal "Cora digest for #{@day.to_fs(:long)}", payload[:text]
    assert_includes rendered, "7 items with new messages"
    assert_includes rendered, "Complaint: 4  |  Praise: 2  |  Question: 1  |  Neutral: 0  |  Relieved: 0"
    assert_includes rendered, "bug (3), praise (2)"
    assert_includes rendered, "worst_day"
    assert_includes rendered, "&gt; Cora lost every email"
    assert_includes rendered, "second_worst"
    assert_includes rendered, "mildly_upset"
    assert_not_includes rendered, "calmest_complainer"
    assert_includes rendered, "big_fan"
    assert_includes rendered, "&gt; Cora saves me an hour a day"
    assert_includes rendered, "/items/#{fan.id}"
    %w[off_topic spiral_person old_news].each { |handle| assert_not_includes rendered, handle }
    assert_includes rendered, "Agents handled 2 items"
    assert_includes rendered, "Cursor 1"
    assert_includes rendered, "Baby Agent 1"
  end

  test "only customer messages count toward the day and the quoted standout" do
    loud = add_item(sentiment: "complaint", anger: 0.9, handle: "loud_customer", body: "Brief never arrived")
    loud.messages.create!(source: loud.source, external_id: SecureRandom.hex(8), body: "Team here, we are on it",
      occurred_at: @noon + 1.hour, author_role: "team")
    old = add_item(sentiment: "complaint", anger: 0.8, occurred_at: @noon - 3.days, handle: "old_thread")
    old.messages.create!(source: old.source, external_id: SecureRandom.hex(8), body: "Following up from Every",
      occurred_at: @noon, author_role: "team")

    rendered = Slack::DigestMessage.new(products(:cora), @day).to_h[:blocks].to_json

    assert_includes rendered, "1 item with new messages"
    assert_includes rendered, "Brief never arrived"
    assert_not_includes rendered, "Team here"
    assert_not_includes rendered, "old_thread"
  end

  test "covers AE8: a product with no items that day gets a quiet-day digest" do
    message = Slack::DigestMessage.new(products(:sparkle), Date.current - 10)

    assert message.quiet?
    assert_includes message.to_h[:blocks].to_json, "Quiet day: no new feedback about Sparkle."
  end

  test "the day boundary follows the app time zone" do
    Time.use_zone("America/Los_Angeles") do
      add_item(sentiment: "praise", occurred_at: Time.utc(2030, 1, 10, 3), handle: "late_night_fan")

      assert_not Slack::DigestMessage.new(products(:cora), Date.new(2030, 1, 9)).quiet?
      assert Slack::DigestMessage.new(products(:cora), Date.new(2030, 1, 10)).quiet?
    end
  end

  private

  def add_item(sentiment:, handle:, product: products(:cora), anger: 0.1, sentiment_probability: 0.9,
    category: nil, relevant: true, occurred_at: @noon, body: "Message from #{handle}")
    item = Item.create!(source: sources(:intercom_inbox), thread_key: "digest-#{SecureRandom.hex(4)}",
      author_handle: handle, product: product, category: category, sentiment: sentiment,
      sentiment_probability: sentiment_probability, anger_probability: anger, relevant: relevant,
      last_message_at: occurred_at)
    item.messages.create!(source: item.source, external_id: SecureRandom.hex(8), body: body,
      occurred_at: occurred_at, anger_probability: anger)
    item
  end

  def report(item, agent, status)
    item.events.create!(kind: :reported, actor: agent, data: { summary: "Done", status: status }, created_at: @noon)
  end
end
