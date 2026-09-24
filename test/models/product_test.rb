require "test_helper"

class ProductTest < ActiveSupport::TestCase
  test "derives a slug from the name and normalizes hint words" do
    product = Product.create!(name: " Monologue ", hint_words: [ " dictation ", "", "voice", "voice" ])

    assert_equal "Monologue", product.name
    assert_equal "monologue", product.slug
    assert_equal %w[dictation voice], product.hint_words
  end

  test "requires unique name and slug" do
    duplicate = Product.new(name: "Cora", slug: "cora")

    refute duplicate.valid?
    assert duplicate.errors.key?(:name)
    assert duplicate.errors.key?(:slug)
  end

  test "digest hour must be an hour of the day" do
    product = products(:cora)
    product.digest_hour = 24

    refute product.valid?
  end

  test "escalation threshold override falls back to the settings default" do
    assert_equal 0.7, products(:spiral).effective_escalation_threshold
    assert_equal 0.8, products(:cora).effective_escalation_threshold
  end

  test "retiring keeps the product and its items readable" do
    product = products(:cora)
    product.retire!

    assert product.reload.retired?
    assert_not_includes Product.active, product
    assert_includes Product.retired, product
    assert_equal product, items(:angry_slack).reload.product

    product.restore!
    assert_includes Product.active, product
  end

  test "cannot be destroyed while items reference it" do
    refute products(:cora).destroy
    assert Product.exists?(products(:cora).id)
  end
end
