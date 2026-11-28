require "test_helper"

class Slack::MentionsTest < ActiveSupport::TestCase
  test "renders user, enterprise grid, and user group IDs in order" do
    rendered = Slack::Mentions.render(%w[U0AGQDHRV8U S0BINGSU01 W0GRIDUSER])

    assert_equal "<@U0AGQDHRV8U> <!subteam^S0BINGSU01> <@W0GRIDUSER>", rendered
  end

  test "accepts the minimum 6-character suffix for U, W, and S IDs" do
    rendered = Slack::Mentions.render(%w[U123456 WABCDEF S9Z8Y7X])

    assert_equal "<@U123456> <@WABCDEF> <!subteam^S9Z8Y7X>", rendered
  end

  test "filters out invalid IDs, display names, non-strings, and multiline strings" do
    ids = [
      "U12345",
      "S12345",
      "C0COMMUNITY",
      "B123456",
      "u123456",
      "U12345a",
      "@ana",
      "U123456 ",
      " U123456",
      "U123456\n<!channel>",
      "",
      nil,
      1234567,
      {},
      "U0VALID1"
    ]

    assert_equal "<@U0VALID1>", Slack::Mentions.render(ids)
  end

  test "returns an empty string when given no valid IDs" do
    assert_equal "", Slack::Mentions.render([])
    assert_equal "", Slack::Mentions.render([ "@channel", "C0COMMUNITY", nil ])
  end
end
