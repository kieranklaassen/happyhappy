require "test_helper"

class Items::CorrectLabelTest < ActiveSupport::TestCase
  test "correcting relevance re-bands actionability" do
    item = items(:not_relevant_slack)
    item.update!(actionability: 0.6, actionability_band: "noise")

    Items::CorrectLabel.call(item: item, label: "relevant", value: "true", actor: users(:one))
    assert_equal "should_reply", item.reload.actionability_band

    Items::CorrectLabel.call(item: item, label: "relevant", value: "false", actor: users(:one))
    assert_equal "noise", item.reload.actionability_band
  end

  setup do
    @item = items(:needs_review_x)
    @user = users(:every_ana)
  end

  test "changing the product marks it human-set, clears review, and writes a corrected event with the user" do
    assert_difference -> { @item.events.count } => 1 do
      assert Items::CorrectLabel.call(item: @item, label: "product", value: products(:cora).id.to_s, actor: @user)
    end

    @item.reload
    assert_equal products(:cora), @item.product
    assert @item.product_human_set
    refute @item.needs_review
    event = @item.events.last
    assert event.corrected?
    assert_equal @user, event.actor
    assert_equal({ "label" => "product", "from" => "Sparkle", "to" => "Cora",
      "from_id" => products(:sparkle).id, "to_id" => products(:cora).id }, event.data)
  end

  test "a blank product means not about any product" do
    Items::CorrectLabel.call(item: @item, label: "product", value: "", actor: @user)

    assert_nil @item.reload.product
    assert_equal({ "label" => "product", "from" => "Sparkle", "to" => nil,
      "from_id" => products(:sparkle).id, "to_id" => nil }, @item.events.last.data)
  end

  test "corrects category, sentiment, and relevance" do
    Items::CorrectLabel.call(item: @item, label: "category", value: categories(:bug).id.to_s, actor: @user)
    Items::CorrectLabel.call(item: @item, label: "sentiment", value: "praise", actor: @user)
    Items::CorrectLabel.call(item: @item, label: "relevant", value: "false", actor: @user)

    @item.reload
    assert_equal categories(:bug), @item.category
    assert @item.status_new?
    assert @item.praise?
    refute @item.relevant
    assert @item.category_human_set && @item.sentiment_human_set && @item.relevant_human_set
    assert_equal [ %w[category other bug], %w[sentiment neutral praise], [ "relevant", true, false ] ],
      @item.events.corrected.last(3).map { |event| event.data.values_at("label", "from", "to") }
  end

  test "setting the same value again marks it human-set without a new event" do
    assert_no_difference -> { @item.events.count } do
      Items::CorrectLabel.call(item: @item, label: "sentiment", value: "neutral", actor: @user)
    end

    assert @item.reload.sentiment_human_set
  end

  test "rejects unknown labels, unknown values, and retired options without changing the item" do
    [
      [ "anger", "0.1" ],
      [ "sentiment", "furious" ],
      [ "relevant", "maybe" ],
      [ "product", "999999" ],
      [ "product", products(:lex).id.to_s ],
      [ "category", categories(:pricing).id.to_s ]
    ].each do |label, value|
      assert_raises(Items::CorrectLabel::Invalid, "#{label}=#{value}") do
        Items::CorrectLabel.call(item: @item, label: label, value: value, actor: @user)
      end
    end

    assert_equal products(:sparkle), @item.reload.product
    refute @item.product_human_set
    assert_equal 1, @item.events.count
  end

  test "keeps a retired product that is already the item's label" do
    item = items(:retired_product_slack)

    Items::CorrectLabel.call(item: item, label: "product", value: products(:lex).id.to_s, actor: @user)

    assert item.reload.product_human_set
    assert_equal products(:lex), item.product
  end
end
