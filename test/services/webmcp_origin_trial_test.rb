require "test_helper"

class WebmcpOriginTrialTest < ActiveSupport::TestCase
  test "reads one token per origin, split on whitespace or commas" do
    env = { "WEBMCP_ORIGIN_TRIAL_TOKEN" => " AbC123+/=, XyZ789==\nQrs456 " }

    assert_equal %w[AbC123+/= XyZ789== Qrs456], WebmcpOriginTrial.tokens_from(env)
  end

  test "an unset or blank variable yields no tokens" do
    assert_equal [], WebmcpOriginTrial.tokens_from({})
    assert_equal [], WebmcpOriginTrial.tokens_from({ "WEBMCP_ORIGIN_TRIAL_TOKEN" => "  " })
  end

  test "drops tokens outside the base64 alphabet instead of putting them in markup" do
    env = { "WEBMCP_ORIGIN_TRIAL_TOKEN" => %(Good123= "><script>alert(1)</script>) }

    assert_equal %w[Good123=], WebmcpOriginTrial.tokens_from(env)
  end
end
