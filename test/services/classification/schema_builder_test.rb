require "test_helper"

class Classification::SchemaBuilderTest < ActiveSupport::TestCase
  setup do
    @questions = Classification::SchemaBuilder.call.questions
  end

  test "asks relevance, product, category, sentiment, and anger in one request" do
    assert_equal %w[relevant product category sentiment anger], @questions.keys
    assert_equal %w[noul choice choice choice noul], @questions.values.pluck("type")
    assert_equal %w[true false], @questions.dig("relevant", "criteria").keys
    assert_equal %w[true false], @questions.dig("anger", "criteria").keys
  end

  test "offers active products by slug with their descriptions and hint words, plus a none option" do
    criteria = @questions.dig("product", "criteria")

    assert_equal %w[cora sparkle spiral none], criteria.keys
    assert_equal(
      { "name" => "Cora", "what" => products(:cora).description, "also_called" => %w[cora brief inbox screener] },
      criteria["cora"]
    )
    assert_equal %w[Cora Sparkle Spiral], @questions.dig("relevant", "instructions", "products").pluck("name")
  end

  test "a retired product is not offered" do
    refute_includes @questions.dig("product", "criteria").keys, "lex"
    refute_includes @questions.dig("relevant", "instructions", "products").pluck("name"), "Lex"
  end

  test "offers active categories by name in position order, keeping a configured other category" do
    criteria = @questions.dig("category", "criteria")

    assert_equal [ "bug", "billing", "feature request", "onboarding", "praise", "other" ], criteria.keys
    assert_equal categories(:other).description, criteria["other"]
    refute_includes criteria.keys, "pricing"
  end

  test "adds an other option when no category is named other" do
    categories(:other).retire!

    criteria = Classification::SchemaBuilder.call.questions.dig("category", "criteria")

    assert_equal "Fits none of the categories above.", criteria["other"]
  end

  test "offers every item sentiment" do
    assert_equal Item.sentiments.keys, @questions.dig("sentiment", "criteria").keys
  end
end
