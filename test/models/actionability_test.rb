require "test_helper"

class ActionabilityTest < ActiveSupport::TestCase
  test "a relevant item is banded by its score and is never noise" do
    assert_equal "act_now", Actionability.band(score: 0.95, relevant: true)
    assert_equal "should_reply", Actionability.band(score: 0.6, relevant: true)
    assert_equal "fyi", Actionability.band(score: 0.05, relevant: true)
    assert_nil Actionability.band(score: nil, relevant: true)
  end

  test "an item that is not relevant is noise whatever it scores" do
    assert_equal "noise", Actionability.band(score: 0.99, relevant: false)
    assert_equal "noise", Actionability.band(score: nil, relevant: false)
  end
end
