# frozen_string_literal: true

require "test_helper"

class MoodTest < ActiveSupport::TestCase
  test "an unclassified item is still being read" do
    assert_equal "pending", Mood.for(sentiment: nil, anger: nil)
  end

  test "anger at the escalation threshold is furious, whatever the sentiment" do
    assert_equal "furious", Mood.for(sentiment: "complaint", anger: 0.8, furious_at: 0.8)
    assert_equal "furious", Mood.for(sentiment: "question", anger: 0.75, furious_at: 0.7)
    assert_equal "grumpy", Mood.for(sentiment: "complaint", anger: 0.79, furious_at: 0.8)
  end

  test "the furious line defaults to the global escalation threshold" do
    Setting.current.update!(escalation_threshold: 0.5)

    assert_equal "furious", Mood.for(sentiment: "complaint", anger: 0.55)
  end

  test "complaints and noticeable anger are grumpy" do
    assert_equal "grumpy", Mood.for(sentiment: "complaint", anger: 0.1, furious_at: 0.8)
    assert_equal "grumpy", Mood.for(sentiment: "neutral", anger: 0.45, furious_at: 0.8)
  end

  test "questions and neutral remarks are meh" do
    assert_equal "meh", Mood.for(sentiment: "question", anger: 0.05, furious_at: 0.8)
    assert_equal "meh", Mood.for(sentiment: "neutral", anger: 0.2, furious_at: 0.8)
  end

  test "confident praise is beaming and softer praise is content" do
    assert_equal "beaming", Mood.for(sentiment: "praise", anger: 0.01, sentiment_probability: 0.9, furious_at: 0.8)
    assert_equal "content", Mood.for(sentiment: "praise", anger: 0.01, sentiment_probability: 0.6, furious_at: 0.8)
  end

  test "relieved is its own mood unless the customer is still furious" do
    assert_equal "relieved", Mood.for(sentiment: "relieved", anger: 0.1, furious_at: 0.8)
    assert_equal "relieved", Mood.for(sentiment: "relieved", anger: 0.5, furious_at: 0.8)
    assert_equal "furious", Mood.for(sentiment: "relieved", anger: 0.85, furious_at: 0.8)
    assert_equal "content", Mood.overall(%w[relieved relieved])
  end

  test "overall mood averages classified moods and ignores pending ones" do
    assert_equal "beaming", Mood.overall(%w[beaming beaming content])
    assert_equal "meh", Mood.overall(%w[beaming furious meh pending])
    assert_equal "grumpy", Mood.overall(%w[grumpy furious meh])
    assert_nil Mood.overall(%w[pending])
    assert_nil Mood.overall([])
  end
end
