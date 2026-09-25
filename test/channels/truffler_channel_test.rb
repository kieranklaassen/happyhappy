require "test_helper"

class TrufflerChannelTest < ActionCable::Channel::TestCase
  test "a signed-in user streams only their own Smart search pings" do
    stub_connection current_user: users(:every_ana)

    subscribe

    assert subscription.confirmed?
    assert_has_stream "truffler:User:#{users(:every_ana).id}"
  end

  test "without a user the subscription is rejected" do
    stub_connection current_user: nil

    subscribe

    assert subscription.rejected?
  end
end
