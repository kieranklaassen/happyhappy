# frozen_string_literal: true

require "test_helper"

class MoodSceneTest < ActiveSupport::TestCase
  def scene(**options)
    MoodScene.new(**options).props
  end

  def characters(props)
    props[:scene].flat_map { |group| group[:characters] }
  end

  def character_for(props, item)
    characters(props).find { |character| character[:item_id] == item.id }
  end

  test "draws relevant people from the last 24 hours, grouped by product name" do
    props = scene

    assert_equal %w[Cora Sparkle], props[:scene].map { |group| group.dig(:product, :name) }
    ids = characters(props).map { |character| character[:item_id] }
    assert_includes ids, items(:angry_slack).id
    assert_includes ids, items(:needs_review_x).id
    assert_not_includes ids, items(:not_relevant_slack).id, "not relevant items stay out"
    assert_not_includes ids, items(:handled_email).id, "four days ago is outside today"
    assert_not_includes ids, items(:retired_product_slack).id
  end

  test "each character carries its mood, latest message, and a link target" do
    angry = character_for(scene, items(:angry_slack))

    assert_equal "furious", angry[:mood]
    assert_equal "Ana Customer", angry[:name]
    assert_equal "@ana_customer", angry[:handle]
    assert_equal "slack", angry[:source_kind]
    assert_equal "Still nothing. Anyone from Every here?", angry[:excerpt]
    assert_match(/\A\h{16}\z/, angry[:seed])
    assert_equal "grumpy", character_for(scene, items(:claimed_intercom))[:mood]
    assert_equal "meh", character_for(scene, items(:needs_review_x))[:mood]
  end

  test "the seed is stable per author and never exposes the address" do
    first = character_for(scene, items(:claimed_intercom))[:seed]

    assert_equal first, character_for(scene, items(:claimed_intercom))[:seed]
    assert_not_includes first, "bo@example.com"
  end

  test "one customer with several threads on a product is one character drawn from the latest thread" do
    newer = items(:claimed_intercom).dup.tap do |item|
      item.update!(thread_key: "215470000000099", author_email: "BO@example.com ", sentiment: "praise",
        sentiment_probability: 0.9, anger_probability: 0.0, last_message_at: 10.minutes.ago, status: "new")
    end

    bo = characters(scene).select { |character| character[:name] == "Bo Billing" }

    assert_equal 1, bo.size
    assert_equal newer.id, bo.first[:item_id]
    assert_equal 2, bo.first[:threads]
    assert_equal "beaming", bo.first[:mood]
  end

  test "furious follows the product's own escalation threshold" do
    item = items(:praise_discord)
    item.update!(sentiment: "complaint", anger_probability: 0.72, last_message_at: 1.hour.ago)

    assert_equal "furious", character_for(scene, item)[:mood], "Spiral escalates at 0.7"
  end

  test "an item waiting for classification is pending" do
    item = items(:needs_review_x)
    item.update!(sentiment: nil, anger_probability: nil)

    assert_equal "pending", character_for(scene, item)[:mood]
  end

  test "a handled complaint is drawn mended" do
    item = items(:angry_slack)
    item.update!(status: "handled")

    assert character_for(scene, item)[:mended]
    assert_not character_for(scene, items(:needs_review_x))[:mended]
  end

  test "the summary counts people by mood" do
    today = scene[:today]

    assert_equal "24h", today[:range]
    assert_equal 3, today[:people]
    assert_equal({ "beaming" => 0, "content" => 0, "meh" => 1, "grumpy" => 1, "furious" => 1, "pending" => 0 }, today[:counts])
    assert_equal 0, today[:smiling]
    assert_equal 2, today[:grumpy]
    assert_equal "grumpy", today[:mood]
  end

  test "each product group has its own mood and counts" do
    cora = scene[:scene].find { |group| group.dig(:product, :slug) == "cora" }

    assert_equal "furious", cora[:mood]
    assert_equal 1, cora[:counts]["furious"]
    assert_equal 1, cora[:counts]["grumpy"]
  end

  test "a product filter narrows the scene and the summary" do
    props = scene(product: products(:sparkle))

    assert_equal [ "Sparkle" ], props[:scene].map { |group| group.dig(:product, :name) }
    assert_equal 1, props[:today][:people]
    assert_equal "sparkle", props[:filters][:product]
  end

  test "the week range reaches older threads and unknown ranges fall back to today" do
    week = characters(scene(range: "7d")).map { |character| character[:item_id] }

    assert_includes week, items(:handled_email).id
    assert_includes week, items(:praise_discord).id
    assert_equal "24h", scene(range: "forever")[:filters][:range]
  end

  test "items with no product gather in their own group at the end" do
    items(:needs_review_x).update!(product: nil)

    assert_nil scene[:scene].last[:product]
  end

  test "a crowded product shows the most recent people and counts the rest" do
    source = sources(:x_mentions)
    (MoodScene::CHARACTERS_PER_PRODUCT + 1).times do |index|
      Item.create!(source: source, product: products(:sparkle), thread_key: "crowd-#{index}",
        author_handle: "fan#{index}", sentiment: "praise", sentiment_probability: 0.9, anger_probability: 0.0,
        last_message_at: index.minutes.ago)
    end

    sparkle = scene[:scene].find { |group| group.dig(:product, :slug) == "sparkle" }

    assert_equal MoodScene::CHARACTERS_PER_PRODUCT, sparkle[:characters].size
    assert_equal 2, sparkle[:overflow]
    assert_equal "@fan0", sparkle[:characters].first[:name]
  end

  test "only active products are offered as filters" do
    slugs = scene[:options][:products].map { |product| product[:slug] }

    assert_equal %w[cora sparkle spiral], slugs
  end
end
