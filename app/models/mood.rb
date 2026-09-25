# frozen_string_literal: true

# How a customer seems, derived from an item's classification. The dashboard
# draws one face per mood, so these rules are the single source of truth for
# what "furious" or "meh" means.
module Mood
  ALL = %w[beaming content relieved meh grumpy furious].freeze
  PENDING = "pending"

  SCORES = { "beaming" => 2, "content" => 1, "relieved" => 1, "meh" => 0, "grumpy" => -1, "furious" => -2 }.freeze

  GRUMPY_ANGER = 0.45
  BEAMING_PRAISE = 0.75

  module_function

  # Furious means the item would escalate, so the storm cloud and the Slack
  # escalation always agree. Relieved is a customer who was upset earlier in the
  # thread and is satisfied now.
  def for(sentiment:, anger:, sentiment_probability: nil, furious_at: Setting.current.escalation_threshold)
    return PENDING if sentiment.nil? && anger.nil?

    anger = anger.to_f
    return "furious" if anger >= furious_at
    return "relieved" if sentiment == "relieved"
    return "grumpy" if sentiment == "complaint" || anger >= GRUMPY_ANGER
    return "meh" unless sentiment == "praise"

    sentiment_probability.to_f >= BEAMING_PRAISE ? "beaming" : "content"
  end

  # Averages the scores of classified moods; nil when nobody has a mood yet.
  def overall(moods)
    scores = moods.filter_map { |mood| SCORES[mood] }
    return nil if scores.empty?

    from_score(scores.sum.to_f / scores.size)
  end

  def from_score(score)
    if score >= 1.2 then "beaming"
    elsif score >= 0.4 then "content"
    elsif score > -0.4 then "meh"
    elsif score > -1.2 then "grumpy"
    else "furious"
    end
  end
end
