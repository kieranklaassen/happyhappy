require "test_helper"
require "rake"

class ClassificationsRakeTest < ActiveSupport::TestCase
  setup do
    @previous_item_ids = ENV["ITEM_IDS"]
    ENV.delete("ITEM_IDS")
    Rails.application.load_tasks unless Rake::Task.task_defined?("classifications:rerun")
    Rake::Task["classifications:rerun"].reenable
  end

  teardown do
    if @previous_item_ids.nil?
      ENV.delete("ITEM_IDS")
    else
      ENV["ITEM_IDS"] = @previous_item_ids
    end
    Current.reset
  end

  test "classifications:rerun runs across all items in id order with Current.backfill enabled" do
    captured = {}
    stats = { items: 7, messages: 8, reclassified: 2, skipped: 6, failed: 0 }

    out, = stub_rerun(lambda { |items:, logger:|
      captured[:item_ids] = items.pluck(:id)
      captured[:logger] = logger
      captured[:backfill_on_new] = Current.backfill
      -> do
        captured[:backfill_on_call] = Current.backfill
        logger.info("[rerun] progress")
        stats
      end
    }) do
      capture_io { Rake::Task["classifications:rerun"].invoke }
    end

    assert_equal Item.order(:id).pluck(:id), captured[:item_ids]
    assert_instance_of ActiveSupport::Logger, captured[:logger]
    assert_equal true, captured[:backfill_on_new]
    assert_equal true, captured[:backfill_on_call]
    assert_nil Current.backfill
    assert_includes out, "[rerun] progress"
    assert_includes out, "rerun finished: #{stats}\n"
  end

  test "classifications:rerun limits items to ITEM_IDS in id order" do
    selected = [ items(:handled_email), items(:angry_slack) ].sort_by(&:id)
    ENV["ITEM_IDS"] = "#{selected.last.id},#{selected.first.id}"
    captured = {}
    stats = { items: 2, messages: 3, reclassified: 3 }

    out, = stub_rerun(lambda { |items:, logger:|
      captured[:item_ids] = items.pluck(:id)
      -> do
        captured[:backfill_on_call] = Current.backfill
        stats
      end
    }) do
      capture_io { Rake::Task["classifications:rerun"].invoke }
    end

    assert_equal selected.map(&:id), captured[:item_ids]
    assert_equal true, captured[:backfill_on_call]
    assert_nil Current.backfill
    assert_equal "rerun finished: #{stats}\n", out
  end

  test "classifications:rerun ignores blank ITEM_IDS and processes all items" do
    ENV["ITEM_IDS"] = "   "
    captured_ids = nil

    out, = stub_rerun(lambda { |items:, logger:|
      captured_ids = items.pluck(:id)
      -> { { items: captured_ids.size } }
    }) do
      capture_io { Rake::Task["classifications:rerun"].invoke }
    end

    assert_equal Item.order(:id).pluck(:id), captured_ids
    assert_equal "rerun finished: #{{ items: captured_ids.size }}\n", out
  end

  test "classifications:rerun resets Current.backfill when rerun raises" do
    backfill_on_call = nil

    stub_rerun(lambda { |items:, logger:|
      -> do
        backfill_on_call = Current.backfill
        raise "rerun exploded"
      end
    }) do
      error = assert_raises(RuntimeError) do
        capture_io { Rake::Task["classifications:rerun"].invoke }
      end
      assert_equal "rerun exploded", error.message
    end

    assert_equal true, backfill_on_call
    assert_nil Current.backfill
  end

  private

  def stub_rerun(factory)
    own_method = Classification::Rerun.singleton_class.method_defined?(:new, false)
    original = Classification::Rerun.method(:new) if own_method
    Classification::Rerun.define_singleton_method(:new) do |items:, logger:|
      runner = factory.call(items: items, logger: logger)
      Struct.new(:callable) do
        def call = callable.call
      end.new(runner)
    end
    yield
  ensure
    if own_method
      Classification::Rerun.define_singleton_method(:new, original)
    else
      Classification::Rerun.singleton_class.remove_method(:new)
    end
  end
end
