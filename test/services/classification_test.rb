require "test_helper"

class ClassificationTest < ActiveSupport::TestCase
  test "the fake classifier returns canned TypeSafe-shaped answers and records calls" do
    fake = use_fake_classifier(product: "spiral", product_probability: 0.45, anger: 0.85)
    message = messages(:praise_discord_first)

    answers = Classification.classifier.call(message)

    assert_same fake, Classification.classifier
    assert_equal [ message ], fake.calls
    assert_equal({ "type" => "noul", "noul" => 0.85 }, answers["anger"])
    assert_equal "spiral", answers.dig("product", "choice")
    assert_equal({ "spiral" => 0.45, "none" => 0.55 }, answers.dig("product", "probabilities"))
    assert_equal "complaint", answers.dig("sentiment", "choice")
    assert_equal %w[complaint praise question neutral].sort, answers.dig("sentiment", "probabilities").keys.sort
    assert_equal %w[relevant product category sentiment anger], answers.keys
  end

  test "the fake classifier accepts a callable and can fail every call" do
    fake = use_fake_classifier(->(message) { { "echo" => message.body } })
    assert_equal({ "echo" => "anyone up for lunch?" }, fake.call(messages(:not_relevant_slack_first)))

    fake.fail_with(RubyLLM::ServerError.new("boom"))
    assert_raises(RubyLLM::ServerError) { fake.call(messages(:not_relevant_slack_first)) }
  end

  test "with_fake_classifier restores the default seam afterwards" do
    with_fake_classifier(anger: 0.9) do |fake|
      assert_same fake, Classification.classifier
    end

    assert_instance_of Classification::Classifier, Classification.classifier
  end
end
