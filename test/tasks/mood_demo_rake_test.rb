require "test_helper"
require "rake"

class MoodDemoRakeTest < ActiveSupport::TestCase
  TASKS = %w[mood:demo mood:drift].freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("mood:demo")
    TASKS.each { |name| Rake::Task[name].reenable }
  end

  test "MoodDemo.source creates a demo source and reuses it on repeat calls" do
    source = assert_difference -> { Source.count } => 1 do
      MoodDemo.source("slack")
    end

    assert_equal "slack", source.kind
    assert_equal "demo-slack", source.selector
    assert_equal "Demo slack", source.name
    assert_equal source, MoodDemo.source("slack")
  end

  test "MoodDemo.product reuses existing products, creates missing ones, and rejects unknown slugs" do
    assert_equal products(:cora), MoodDemo.product("cora")

    monologue = assert_difference -> { Product.count } => 1 do
      MoodDemo.product("monologue")
    end
    assert_equal "monologue", monologue.slug
    assert_equal "Monologue", monologue.name
    assert_equal MoodDemo::PRODUCTS["monologue"][1], monologue.description
    assert_equal MoodDemo::PRODUCTS["monologue"][2], monologue.search_blurb
    assert_equal monologue, MoodDemo.product("monologue")

    assert_raises(KeyError) { MoodDemo.product("unknown") }
  end

  test "MoodDemo.author maps email addresses and handles" do
    assert_equal({ author_email: "bo@example.com", author_name: "Bo" }, MoodDemo.author("bo@example.com"))
    assert_equal({ author_handle: "ana_customer" }, MoodDemo.author("ana_customer"))
  end

  test "MoodDemo.demo_message! creates a message and updates it idempotently by external_id" do
    item = items(:angry_slack)
    first_at = 2.hours.ago.change(usec: 0)
    second_at = 1.hour.ago.change(usec: 0)

    assert_difference -> { item.messages.count } => 1 do
      MoodDemo.demo_message!(item, "demo-msg-1", first_at, "Initial text")
    end

    message = item.messages.find_by!(external_id: "demo-msg-1")
    assert_equal "Initial text", message.body
    assert_equal 0.1, message.anger_probability
    assert_equal first_at, message.occurred_at
    assert_equal first_at, message.classified_at

    assert_no_difference -> { item.messages.count } do
      MoodDemo.demo_message!(item, "demo-msg-1", second_at, "Updated text", anger: 0.8)
    end

    message.reload
    assert_equal "Updated text", message.body
    assert_equal 0.8, message.anger_probability
    assert_equal second_at, message.occurred_at
    assert_equal second_at, message.classified_at
  end

  test "MoodDemo.classify! records both classified and unclassified messages" do
    item = items(:not_relevant_slack)
    at = 10.minutes.ago.change(usec: 0)

    assert_difference -> { item.messages.count } => 1 do
      MoodDemo.classify!(item, sentiment: "complaint", confidence: 0.9, anger: 0.85, body: "Broken export", at: at)
    end

    item.reload
    classified_message = item.messages.last
    assert_equal "complaint", item.sentiment
    assert_equal 0.9, item.sentiment_probability
    assert_equal 0.85, item.anger_probability
    assert_equal true, item.relevant
    assert_equal at, item.last_message_at
    assert_equal "Broken export", classified_message.body
    assert_not_nil classified_message.classified_at

    later = 2.minutes.ago.change(usec: 0)
    assert_difference -> { item.messages.count } => 1 do
      MoodDemo.classify!(item, sentiment: nil, confidence: nil, anger: nil, body: "Just arrived", at: later)
    end

    item.reload
    unclassified_message = item.messages.last
    assert_nil item.sentiment
    assert_nil item.sentiment_probability
    assert_nil item.anger_probability
    assert_equal true, item.relevant
    assert_equal later, item.last_message_at
    assert_nil unclassified_message.classified_at
  end

  test "MoodDemo.seed_burst! tags loud items and seeds baseline and burst messages idempotently" do
    freeze_time do
      source = MoodDemo.source("slack")
      cora = products(:cora)
      quiet_items = %w[q1 q2].map do |author|
        Item.create!(source: source, product: cora, thread_key: "demo-#{author}", last_message_at: 1.day.ago)
      end
      loud_items = %w[l1 l2].map do |author|
        Item.create!(source: source, product: cora, thread_key: "demo-#{author}", last_message_at: 1.day.ago)
      end

      assert_difference -> { Message.count } => 26 do
        MoodDemo.seed_burst!(
          category: "bug",
          description: "Something is broken.",
          quiet: %w[q1 q2],
          loud: %w[l1 l2],
          tag: "test",
          body: "Burst failure",
          anger: 0.8
        )
      end

      loud_items.each { |item| assert_equal "bug", item.reload.category.name }
      quiet_items.each { |item| assert_nil item.reload.category }

      last_window_start, last_window_end = Anomalies::Detect.windows("hour").last
      baseline_messages = Message.where("external_id LIKE 'demo-test-baseline-%'")
      burst_messages = Message.where("external_id LIKE 'demo-test-burst-%'")
      assert_equal 18, baseline_messages.count
      assert_equal 8, burst_messages.count
      assert baseline_messages.all? { |message| message.occurred_at < last_window_start }
      assert burst_messages.all? { |message|
        message.body == "Burst failure" && message.anger_probability == 0.8 &&
          message.occurred_at >= last_window_start && message.occurred_at < last_window_end
      }

      assert_no_difference -> { Message.count } do
        MoodDemo.seed_burst!(
          category: "bug",
          description: "Something is broken.",
          quiet: %w[q1 q2],
          loud: %w[l1 l2],
          tag: "test",
          body: "Burst failure",
          anger: 0.8
        )
      end
    end
  end

  test "MoodDemo.seed_anomaly! seeds Cora bug and Spiral praise bursts and calls hourly anomaly detection" do
    freeze_time do
      source = MoodDemo.source("slack")
      (MoodDemo::BUG_REPORTERS + MoodDemo::QUIET_CORA).each do |author|
        Item.create!(source: source, product: products(:cora), thread_key: "demo-#{author}", last_message_at: 1.day.ago)
      end
      (MoodDemo::FANS + MoodDemo::QUIET_SPIRAL).each do |author|
        Item.create!(source: source, product: products(:spiral), thread_key: "demo-#{author}", last_message_at: 1.day.ago)
      end

      detected_granularity = nil
      result = stub_singleton(Anomalies::Detect, :call, lambda { |granularity:|
        detected_granularity = granularity
        [ :stub_anomaly ]
      }) do
        MoodDemo.seed_anomaly!
      end

      assert_equal "hour", detected_granularity
      assert_equal [ :stub_anomaly ], result
      assert_equal 8, Message.where("external_id LIKE 'demo-anomaly-burst-%'").count
      assert_equal 8, Message.where("external_id LIKE 'demo-praise-burst-%'").count
      assert_equal "bug", Item.find_by!(thread_key: "demo-#{MoodDemo::BUG_REPORTERS.first}").category.name
      assert_equal "praise", Item.find_by!(thread_key: "demo-#{MoodDemo::FANS.first}").category.name
    end
  end

  test "mood:demo aborts outside development" do
    _, err = capture_io do
      assert_raises(SystemExit) { Rake::Task["mood:demo"].invoke }
    end

    assert_includes err, "mood:demo only runs in development"
  end

  test "mood:drift aborts outside development" do
    _, err = capture_io do
      assert_raises(SystemExit) { Rake::Task["mood:drift"].invoke }
    end

    assert_includes err, "mood:drift only runs in development"
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
