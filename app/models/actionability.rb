# How much an item needs someone at Every to act, from the classifier's
# actionable Noul on the customer's current message (Classification::Apply).
# The band is what the feed, MCP, webhooks, escalations, and the digest read:
#
#   act_now       a blocked, charged, cancelling, angry, or waiting customer
#   should_reply  a real question or request that is not urgent
#   fyi           relevant, but nothing to do: praise, thanks, resolved threads
#   noise         not relevant: spam, pitches, automated mail, small talk
#
# A relevant item is never noise, so it stays visible even when it needs
# nothing; an item that is not relevant is always noise.
module Actionability
  BANDS = %w[act_now should_reply fyi noise].freeze
  ACTIONABLE_BANDS = %w[act_now should_reply].freeze
  ACT_NOW = 0.9
  SHOULD_REPLY = 0.4

  module_function

  def band(score:, relevant:)
    return "noise" unless relevant
    return if score.nil?

    if score >= ACT_NOW then "act_now"
    elsif score >= SHOULD_REPLY then "should_reply"
    else "fyi"
    end
  end
end
