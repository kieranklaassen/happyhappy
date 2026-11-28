require "test_helper"

class Items::InboundMessageTest < ActiveSupport::TestCase
  test "defaults occurred_at to now, body to empty string, and raw_payload to an independent hash" do
    freeze_time do
      first = Items::InboundMessage.new(external_id: "m-1", thread_key: "t-1")
      second = Items::InboundMessage.new(external_id: "m-2", thread_key: "t-2")

      assert first.valid?
      assert_equal Time.current, first.occurred_at
      assert_equal "", first.body
      assert_equal({}, first.raw_payload)
      assert_nil first.author_handle
      assert_nil first.author_name
      assert_nil first.author_email
      assert_nil first.permalink

      first.raw_payload["source"] = "slack"
      assert_equal({}, second.raw_payload)
    end
  end

  test "coerces nil and non-string body values to strings while preserving explicit attributes" do
    occurred_at = Time.utc(2026, 5, 1, 12, 30, 0)
    message = Items::InboundMessage.new(
      external_id: "m-1",
      thread_key: "t-1",
      body: nil,
      occurred_at: occurred_at,
      author_handle: "ana_customer",
      author_name: "Ana Customer",
      author_email: "ana@example.com",
      permalink: "https://example.com/messages/1",
      raw_payload: { "id" => "m-1" }
    )

    assert message.valid?
    assert_equal "", message.body
    assert_equal occurred_at, message.occurred_at
    assert_equal "ana_customer", message.author_handle
    assert_equal "Ana Customer", message.author_name
    assert_equal "ana@example.com", message.author_email
    assert_equal "https://example.com/messages/1", message.permalink
    assert_equal({ "id" => "m-1" }, message.raw_payload)

    numeric_body = Items::InboundMessage.new(external_id: "m-2", thread_key: "t-2", body: 404)
    assert_equal "404", numeric_body.body
  end

  test "casts string occurred_at values and falls back to now when nil" do
    freeze_time do
      from_string = Items::InboundMessage.new(
        external_id: "m-1",
        thread_key: "t-1",
        occurred_at: "2026-05-01T12:30:00Z"
      )
      assert_equal Time.utc(2026, 5, 1, 12, 30, 0), from_string.occurred_at

      from_nil = Items::InboundMessage.new(external_id: "m-2", thread_key: "t-2", occurred_at: nil)
      assert_equal Time.current, from_nil.occurred_at
    end
  end

  test "requires external_id, thread_key, and occurred_at" do
    missing_external_id = Items::InboundMessage.new(external_id: "  ", thread_key: "t-1")
    assert_not missing_external_id.valid?
    assert missing_external_id.errors.key?(:external_id)

    missing_thread_key = Items::InboundMessage.new(external_id: "m-1", thread_key: "")
    assert_not missing_thread_key.valid?
    assert missing_thread_key.errors.key?(:thread_key)

    cleared_occurred_at = Items::InboundMessage.new(external_id: "m-1", thread_key: "t-1")
    cleared_occurred_at.occurred_at = nil
    assert_not cleared_occurred_at.valid?
    assert cleared_occurred_at.errors.key?(:occurred_at)
  end

  test "validates that raw_payload is a hash" do
    [ {}, { "id" => "1" }, ActiveSupport::HashWithIndifferentAccess.new(id: "1") ].each do |payload|
      message = Items::InboundMessage.new(external_id: "m-1", thread_key: "t-1", raw_payload: payload)
      assert message.valid?, "expected #{payload.class} raw_payload to be valid"
    end

    [ nil, [], "{}", 123 ].each do |payload|
      message = Items::InboundMessage.new(external_id: "m-1", thread_key: "t-1", raw_payload: payload)
      assert_not message.valid?, "expected #{payload.inspect} raw_payload to be invalid"
      assert_includes message.errors[:raw_payload], "must be a hash"
    end
  end
end
