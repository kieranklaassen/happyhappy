# frozen_string_literal: true

require "test_helper"

class MoodChannelTest < ActionCable::Channel::TestCase
  include ActionCable::TestHelper

  test "subscribing streams the mood pings" do
    stub_connection current_user: users(:one)

    subscribe

    assert subscription.confirmed?
    assert_has_stream MoodChannel::STREAM
  end

  test "a changed item pings open dashboards without customer data" do
    assert_broadcasts(MoodChannel::STREAM, 1) do
      items(:angry_slack).update!(anger_probability: 0.95)
    end

    payload = broadcasts(MoodChannel::STREAM).last
    assert_equal %w[changed_at], ActiveSupport::JSON.decode(payload).keys
  end

  test "a broken cable never fails the item save" do
    ActionCable.server.define_singleton_method(:broadcast) { |*| raise "cable down" }

    assert_error_reported(RuntimeError) do
      assert items(:angry_slack).update!(anger_probability: 0.5)
    end
  ensure
    ActionCable.server.singleton_class.remove_method(:broadcast)
  end
end
