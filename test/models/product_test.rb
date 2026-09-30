require "test_helper"

class ProductTest < ActiveSupport::TestCase
  test "derives a slug from the name and normalizes hint words" do
    product = Product.create!(name: " Monologue ", hint_words: [ " dictation ", "", "voice", "voice" ])

    assert_equal "Monologue", product.name
    assert_equal "monologue", product.slug
    assert_equal %w[dictation voice], product.hint_words
  end

  test "search blurb defaults to the name, is squished, and stays short" do
    product = Product.create!(name: "Monologue", search_blurb: "  ")
    assert_equal "Monologue", product.search_blurb

    product.update!(search_blurb: "  Monologue   dictation ")
    assert_equal "Monologue dictation", product.search_blurb

    product.search_blurb = "x" * (SearchBlurb::MAX_LENGTH + 1)
    refute product.valid?
    assert product.errors.key?(:search_blurb)
  end

  test "the product search option matches the blurb while Jev reads the description and hint words" do
    option = Item::Searchable.product_options.fetch("cora")

    assert_equal "Cora assistant", option[:search]
    assert_includes option[:description], "screener"
  end

  test "requires unique name and slug" do
    duplicate = Product.new(name: "Cora", slug: "cora")

    refute duplicate.valid?
    assert duplicate.errors.key?(:name)
    assert duplicate.errors.key?(:slug)
  end

  test "incident alerts take a channel ID and Slack user or user group IDs to mention" do
    product = products(:cora)
    product.update!(alert_channel_id: " C0AGCDCD6KG ", alert_mention_ids: "U0AGQDHRV8U, S0BINGSU01 W0GRIDUSER")

    assert_equal "C0AGCDCD6KG", product.alert_channel_id
    assert_equal %w[U0AGQDHRV8U S0BINGSU01 W0GRIDUSER], product.alert_mention_ids
    assert_equal "<@U0AGQDHRV8U> <!subteam^S0BINGSU01> <@W0GRIDUSER>", Slack::Mentions.render(product.alert_mention_ids)

    product.alert_mention_ids = "U0AGQDHRV8U, @bingsu, <!channel>"
    product.alert_channel_id = "#cora-alerts"
    assert_not product.valid?
    assert_includes product.errors[:alert_mention_ids].sole, "@bingsu, <!channel>"
    assert product.errors[:alert_channel_id].any?
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
