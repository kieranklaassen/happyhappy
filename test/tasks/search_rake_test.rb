require "test_helper"
require "rake"

class SearchRakeTest < ActiveSupport::TestCase
  TASKS = %w[search:reindex search:demo].freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("search:reindex")
    TASKS.each { |name| Rake::Task[name].reenable }
  end

  test "SearchDemo.category reuses existing categories and creates missing ones" do
    existing = categories(:billing)
    assert_equal existing, SearchDemo.category("billing")

    created = assert_difference -> { Category.count } => 1 do
      SearchDemo.category("question")
    end
    assert_equal "question", created.name
    assert_equal SearchDemo::CATEGORIES["question"], created.description
    assert_equal created, SearchDemo.category("question")

    assert_raises(KeyError) { SearchDemo.category("nonexistent") }
  end

  test "SearchDemo.product creates thesis idempotently and delegates other slugs to MoodDemo" do
    thesis = assert_difference -> { Product.count } => 1 do
      SearchDemo.product("thesis")
    end
    assert_equal "thesis", thesis.slug
    assert_equal "Thesis", thesis.name
    assert_equal SearchDemo::THESIS[1], thesis.description
    assert_equal SearchDemo::THESIS[2], thesis.search_blurb
    assert_equal thesis, SearchDemo.product("thesis")

    assert_equal products(:cora), SearchDemo.product("cora")

    monologue = assert_difference -> { Product.count } => 1 do
      SearchDemo.product("monologue")
    end
    assert_equal "Monologue", monologue.name
  end

  test "SearchDemo.classify! updates category, relevance, actionability, and derived band" do
    item = items(:not_relevant_slack)
    billing = categories(:billing)

    SearchDemo.classify!(item, category: billing, actionability: 0.92)

    item.reload
    assert_equal billing, item.category
    assert_equal 0.95, item.relevance_probability
    assert_equal true, item.relevant
    assert_equal 0.92, item.actionability
    assert_equal "act_now", item.actionability_band

    SearchDemo.classify!(item, category: billing, actionability: 0.1)
    assert_equal "fyi", item.reload.actionability_band
  end

  test "SearchDemo.complete_mood_demo! completes classified demo items and ignores unclassified or non-demo items" do
    source = sources(:slack_community)
    cora = products(:cora)

    praise_item = Item.create!(source: source, product: cora, thread_key: "demo-praise",
      sentiment: "praise", anger_probability: 0.02, last_message_at: 1.hour.ago)
    question_item = Item.create!(source: source, product: cora, thread_key: "demo-question",
      sentiment: "question", anger_probability: 0.25, last_message_at: 1.hour.ago)
    furious_bug = Item.create!(source: source, product: cora, thread_key: "demo-bug",
      sentiment: "complaint", anger_probability: 0.95, last_message_at: 1.hour.ago)
    billing_complaint = Item.create!(source: source, product: cora, thread_key: "demo-billing",
      sentiment: "complaint", category: categories(:billing), anger_probability: 0.5, last_message_at: 1.hour.ago)
    unclassified_demo = Item.create!(source: source, product: cora, thread_key: "demo-unclassified",
      sentiment: nil, last_message_at: 1.hour.ago)
    non_demo = Item.create!(source: source, product: cora, thread_key: "regular-item",
      sentiment: "praise", anger_probability: 0.01, last_message_at: 1.hour.ago)

    SearchDemo.complete_mood_demo!

    praise_item.reload
    assert_equal "praise", praise_item.category.name
    assert_equal 0.1, praise_item.actionability
    assert_equal "fyi", praise_item.actionability_band
    assert_equal true, praise_item.relevant

    question_item.reload
    assert_equal "question", question_item.category.name
    assert_in_delta 0.35, question_item.actionability, 0.001
    assert_equal "fyi", question_item.actionability_band

    furious_bug.reload
    assert_equal "bug", furious_bug.category.name
    assert_equal 0.99, furious_bug.actionability
    assert_equal "act_now", furious_bug.actionability_band

    billing_complaint.reload
    assert_equal "billing", billing_complaint.category.name
    assert_in_delta 0.6, billing_complaint.actionability, 0.001
    assert_equal "should_reply", billing_complaint.actionability_band

    assert_nil unclassified_demo.reload.actionability
    assert_nil non_demo.reload.actionability
  end

  test "SearchDemo.seed! creates all search demo items and reuses them on re-run" do
    assert_difference -> { Item.count } => SearchDemo::ITEMS.size do
      SearchDemo.seed!
    end

    assert_no_difference -> { Item.count } do
      SearchDemo.seed!
    end

    thesis_item = Item.find_by!(source_kind: "discord", thread_key: "search-demo-phd_pat")
    assert_equal "thesis", thesis_item.product.slug
    assert_equal "praise", thesis_item.category.name
    assert_equal "phd_pat", thesis_item.author_handle
    assert_equal "fyi", thesis_item.actionability_band

    billing_item = Item.find_by!(source_kind: "intercom", thread_key: "search-demo-rae@example.com")
    assert_equal "cora", billing_item.product.slug
    assert_equal "billing", billing_item.category.name
    assert_equal "rae@example.com", billing_item.author_email
    assert_equal "Rae", billing_item.author_name
    assert_equal "act_now", billing_item.actionability_band
    assert_includes billing_item.messages.last.body, "Cora billed me three times"
  end

  test "SearchDemo.reindex! rebuilds the text index and refreshes supplied labels" do
    item = items(:angry_slack)
    Item.connection.exec_delete("DELETE FROM #{FeedSearch::TextIndex::TABLE} WHERE rowid = #{item.id}")
    Truffler::Records::Label.where(record_type: "Item", record_id: item.id).delete_all
    assert_empty FeedSearch::TextIndex.matching(Item.where(id: item.id), %w[furious])

    SearchDemo.reindex!

    assert_includes FeedSearch::TextIndex.matching(Item.where(id: item.id), %w[furious]), item
    assert Truffler::Records::Label.where(record_type: "Item", record_id: item.id, label_key: "sentiment:complaint", value: 1.0).exists?
    assert_empty Truffler.config.client.calls
  end

  test "search:reindex invokes SearchDemo.reindex! and prints the indexed item count" do
    reindexed = false
    out, = stub_singleton(SearchDemo, :reindex!, -> { reindexed = true }) do
      capture_io { Rake::Task["search:reindex"].invoke }
    end

    assert reindexed
    assert_equal "Indexed #{Item.count} items.\n", out
  end

  test "search:demo aborts outside development" do
    _, err = capture_io do
      assert_raises(SystemExit) { Rake::Task["search:demo"].invoke }
    end

    assert_includes err, "search:demo only runs in development"
  end

  private

  def stub_singleton(target, method_name, replacement)
    own_method = target.singleton_class.method_defined?(method_name, false)
    original = target.method(method_name) if own_method
    target.define_singleton_method(method_name, &replacement)
    yield
  ensure
    if own_method
      target.define_singleton_method(method_name, original)
    else
      target.singleton_class.remove_method(method_name)
    end
  end
end
