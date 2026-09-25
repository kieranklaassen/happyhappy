# Stands in for TypeSafe Jev in tests (KTD9). Returns canned answers in the
# shape documented on the Classification module and records every call.
#
#   fake = use_fake_classifier(product: "cora", anger: 0.85)
#   ClassifyMessageJob.perform_now(message)
#   fake.calls # => [message]
#
#   fake.fail_with(RubyLLM::ServerError.new("boom")) # every call raises
class FakeClassifier
  SENTIMENTS = %w[complaint praise question neutral relieved].freeze

  attr_reader :calls

  def self.answers(relevant: 0.95, product: "cora", product_probability: 0.9, category: "bug",
    category_probability: 0.85, sentiment: "complaint", sentiment_probability: 0.8, anger: 0.2, team_author: nil, actionable: 0.6)
    {
      "relevant" => noul(relevant),
      "product" => choice(product, product_probability, fallback: "none"),
      "category" => choice(category, category_probability, fallback: "other"),
      "sentiment" => choice(sentiment, sentiment_probability, others: SENTIMENTS),
      "anger" => noul(anger),
      "actionable" => noul(actionable),
      **(team_author ? { "team_author" => noul(team_author) } : {})
    }
  end

  def self.noul(probability)
    { "type" => "noul", "noul" => probability }
  end

  def self.choice(winner, probability, fallback: nil, others: [])
    losers = (others + [ fallback ]).compact.uniq - [ winner ]
    share = losers.empty? ? 0.0 : ((1.0 - probability) / losers.size).round(4)
    probabilities = { winner => probability }.merge(losers.index_with { share })
    { "type" => "choice", "choice" => winner, "probabilities" => probabilities, "confidence" => probability }
  end

  # answers: a hash, or a callable taking the message and returning a hash.
  def initialize(answers = self.class.answers)
    @answers = answers
    @calls = []
    @error = nil
  end

  def call(message)
    @calls << message
    raise @error if @error

    (@answers.respond_to?(:call) ? @answers.call(message) : @answers).deep_dup
  end

  def fail_with(error)
    @error = error
    self
  end
end

module FakeClassifierHelper
  def use_fake_classifier(answers = nil, **options)
    fake = FakeClassifier.new(answers || FakeClassifier.answers(**options))
    Classification.classifier = fake
    fake
  end

  def with_fake_classifier(answers = nil, **options)
    yield use_fake_classifier(answers, **options)
  ensure
    Classification.classifier = nil
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include FakeClassifierHelper
  teardown { Classification.classifier = nil }
end
