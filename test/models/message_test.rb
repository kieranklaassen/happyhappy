require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "external id is unique per source" do
    duplicate = Message.new(item: items(:angry_slack), source: sources(:slack_community),
      external_id: messages(:angry_slack_first).external_id, occurred_at: Time.current)

    refute duplicate.valid?
    assert duplicate.errors.key?(:external_id)
  end

  test "the same external id on another source is allowed" do
    message = Message.new(item: items(:angry_slack), source: sources(:lex_legacy),
      external_id: messages(:angry_slack_first).external_id, occurred_at: Time.current)

    assert message.valid?, message.errors.full_messages.to_sentence
  end

  test "requires an external id" do
    refute Message.new(item: items(:angry_slack), source: sources(:slack_community), occurred_at: Time.current).valid?
  end

  test "stores raw payload and classification answers as JSON" do
    message = messages(:angry_slack_first)

    assert_equal "C0COMMUNITY", message.raw_payload["channel"]
    assert_equal "cora", message.classification_answers.dig("product", "choice")
    assert message.classified?
    refute messages(:unclassified_slack_reply).classified?
    assert_includes Message.unclassified, messages(:unclassified_slack_reply)
  end

  test "a reply that is only an email address is not worth quoting" do
    assert Message.new(body: "I was charged twice").substantive?
    assert_not Message.new(body: " christoph@cambuildr.com ").substantive?
    assert_not Message.new(body: "mailto:dana@example.com").substantive?
    assert_not Message.new(body: "").substantive?
    assert Message.new(body: "Please write to dana@example.com instead").substantive?

    question = Message.new(body: "Why was I charged?")
    email = Message.new(body: "dana@example.com")
    assert_equal question, Message.quotable([ question, email ])
    assert_equal email, Message.quotable([ email ])
    assert_nil Message.quotable([])
  end
end
