require "test_helper"

class Item::SearchableTest < ActiveSupport::TestCase
  include TrufflerHelper
  include ActiveJob::TestHelper

  ASKED = %w[churn_risk].freeze

  def labels(item)
    Truffler::Records::Label.where(record_type: "Item", record_id: item.id).pluck(:label_key, :value).to_h
  end

  test "Jev is asked only churn_risk; every other label is supplied from classification" do
    definition = Item.truffler_definition

    assert_equal ASKED, definition.labels.keys.map(&:to_s) - definition.supplied_labels.map(&:key).map(&:to_s)
  end

  test "refreshing supplied labels writes what classification answered, with no Jev call" do
    fake = truffler_fake
    item = items(:angry_slack)
    item.update_columns(actionability: 0.8, status: "claimed")

    item.truffler_refresh_labels!
    written = labels(item)

    assert_empty fake.calls
    assert_in_delta 0.86, written.fetch("anger")
    assert_in_delta 0.8, written.fetch("needs_action")
    assert_equal 1.0, written.fetch("product:cora")
    assert_equal 1.0, written.fetch("category:bug")
    assert_equal 1.0, written.fetch("sentiment:complaint")
    assert_equal 1.0, written.fetch("status:claimed")
    assert_equal 1.0, written.fetch("source:slack")
    assert_equal 0.0, written.fetch("team_replied")
    assert_not written.key?("churn_risk")
  end

  test "a classified item with no product or category gets the none and other options" do
    item = items(:needs_review_x)
    item.update_columns(product_id: nil, category_id: nil)

    item.truffler_refresh_labels!

    assert_equal 1.0, labels(item).fetch("product:#{Classification::SchemaBuilder::NO_PRODUCT}")
    assert_equal 1.0, labels(item).fetch("category:#{Classification::SchemaBuilder::OTHER_CATEGORY}")
  end

  test "a watched column change rewrites that label, and the labeler asks Jev only churn_risk" do
    fake = truffler_fake(labels: { "churn_risk" => 0.9 })
    item = items(:claimed_intercom)

    perform_enqueued_jobs { item.update!(anger_probability: 0.95) }

    assert_in_delta 0.95, labels(item).fetch("anger")
    assert_in_delta 0.9, labels(item).fetch("churn_risk")
    asked = fake.calls.flat_map { |call| call[:questions].keys }.map { |id| id.split("__").last }.uniq
    assert_equal ASKED, asked
  end

  test "product and category options keep retired ones and always offer none and other" do
    assert_includes Item::Searchable.product_options.keys, products(:lex).slug
    assert_includes Item::Searchable.product_options.keys, Classification::SchemaBuilder::NO_PRODUCT
    assert_includes Item::Searchable.category_options.keys, Classification::SchemaBuilder::OTHER_CATEGORY
  end

  test "the conversation Jev reads is newest first and marks who is on the team" do
    item = items(:angry_slack)
    item.messages.order(:occurred_at).first.update_columns(author_role: "team")

    conversation = item.search_conversation

    assert conversation.start_with?("Customer: Still nothing.")
    assert_includes conversation, "Every team: Cora deleted half my inbox"
  end

  test "any signed-in user may manage feed lenses; agents and anonymous callers may not" do
    policy = Truffler::Lenses::Policy
    app = Truffler::Lenses::Scope.app

    assert policy.allowed?(users(:every_ana), app, model: Item)
    assert policy.allowed?(users(:one), Truffler::Lenses::Scope.user(nil, "User:#{users(:one).id}"), model: Item)
    assert_not policy.allowed?(agents(:cursor), app, model: Item)
    assert_not policy.allowed?(nil, app, model: Item)
  end

  test "truffler asks Jev with the classifier's model, so the account and fingerprints match" do
    assert_equal Classification::Classifier::MODEL, Truffler.config.model
  end
end
