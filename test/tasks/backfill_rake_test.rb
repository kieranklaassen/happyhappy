require "test_helper"
require "rake"

class BackfillRakeTest < ActiveSupport::TestCase
  TASKS = %w[backfill:discord backfill:intercom backfill:intercom_states backfill:status].freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("backfill:discord")
    TASKS.each { |name| Rake::Task[name].reenable }
  end

  test "backfill:discord defaults to 90 days and prints stats and queued count" do
    freeze_time do
      received_since = nil
      discord_stats = build_stats(sources(:discord_spiral), fetched: 5, created: 2, duplicates: 1)
      errored_stats = build_stats(sources(:slack_community), fetched: 3, created: 1, duplicates: 2, error: "HTTP 500")

      out, = stub_singleton(Backfill::Discord, :call, lambda { |since:|
        received_since = since
        [ discord_stats, errored_stats ]
      }) do
        capture_io { Rake::Task["backfill:discord"].invoke }
      end

      assert_equal 90.days.ago, received_since
      assert_equal <<~OUTPUT, out
        #{discord_stats}
        #{errored_stats}
        classification queued for 3 new messages
      OUTPUT
    end
  end

  test "backfill:discord accepts a custom days argument" do
    freeze_time do
      received_since = nil

      out, = stub_singleton(Backfill::Discord, :call, lambda { |since:|
        received_since = since
        []
      }) do
        capture_io { Rake::Task["backfill:discord"].invoke("14") }
      end

      assert_equal 14.days.ago, received_since
      assert_equal "classification queued for 0 new messages\n", out
    end
  end

  test "backfill:discord rejects a non-integer days argument" do
    called = false

    stub_singleton(Backfill::Discord, :call, lambda { |**|
      called = true
      []
    }) do
      assert_raises(ArgumentError) do
        capture_io { Rake::Task["backfill:discord"].invoke("not-a-number") }
      end
    end

    assert_not called
  end

  test "backfill:intercom defaults to 90 days, logs progress, and summarizes stats" do
    freeze_time do
      received_since = nil
      intercom_stats = build_stats(sources(:intercom_inbox), fetched: 4, created: 3, duplicates: 1)

      fake_runner = Struct.new(:progress, :conversations, :stats) do
        def call
          progress.call(100)
          stats
        end
      end

      out, = stub_singleton(Backfill::Intercom, :new, lambda { |since:, progress:|
        received_since = since
        fake_runner.new(progress, 125, [ intercom_stats ])
      }) do
        capture_io { Rake::Task["backfill:intercom"].invoke }
      end

      assert_equal 90.days.ago, received_since
      assert_equal <<~OUTPUT, out
        conversations scanned so far: 100
        conversations scanned: 125
        #{intercom_stats}
        classification queued for 3 new messages
      OUTPUT
    end
  end

  test "backfill:intercom accepts a custom days argument" do
    freeze_time do
      received_since = nil
      fake_runner = Struct.new(:conversations) do
        def call = []
      end

      out, = stub_singleton(Backfill::Intercom, :new, lambda { |since:, progress:|
        received_since = since
        fake_runner.new(0)
      }) do
        capture_io { Rake::Task["backfill:intercom"].invoke("7") }
      end

      assert_equal 7.days.ago, received_since
      assert_equal <<~OUTPUT, out
        conversations scanned: 0
        classification queued for 0 new messages
      OUTPUT
    end
  end

  test "backfill:intercom_states invokes Backfill::IntercomStates and formats counts" do
    counts = { searched: 12, closed: 5, snoozed: 2, open: 3, unchanged: 2, emails: 1 }
    fake_runner = Struct.new(:result) do
      def call = result
    end

    out, = stub_singleton(Backfill::IntercomStates, :new, -> { fake_runner.new(counts) }) do
      capture_io { Rake::Task["backfill:intercom_states"].invoke }
    end

    assert_equal "intercom states: searched=12 closed=5 snoozed=2 open=3 unchanged=2 emails=1\n", out
  end

  test "backfill:status reports per-source backfilled progress and unfinished ClassifyMessageJob jobs" do
    SolidQueue::Job.delete_all

    discord = sources(:discord_spiral)
    intercom = sources(:intercom_inbox)
    discord_item = items(:praise_discord)
    intercom_item = items(:claimed_intercom)

    create_message(discord_item, discord, backfilled: true, classified_at: 1.hour.ago)
    create_message(discord_item, discord, backfilled: true, classified_at: 1.hour.ago, classification_error: "prior error")
    create_message(discord_item, discord, backfilled: true, classified_at: nil, classification_error: "provider timeout")
    create_message(discord_item, discord, backfilled: true, classified_at: nil, classification_error: nil)
    create_message(discord_item, discord, backfilled: false, classified_at: nil, classification_error: nil)
    create_message(intercom_item, intercom, backfilled: true, classified_at: nil, classification_error: nil)

    2.times { SolidQueue::Job.create!(queue_name: "backfill", class_name: "ClassifyMessageJob", finished_at: nil) }
    SolidQueue::Job.create!(queue_name: "backfill", class_name: "ClassifyMessageJob", finished_at: 1.minute.ago)
    SolidQueue::Job.create!(queue_name: "default", class_name: "PostDigestJob", finished_at: nil)

    out, = capture_io { Rake::Task["backfill:status"].invoke }

    assert_includes out, "source #{discord.id} #{discord.name}: backfilled=4 classified=2 failed=1 pending=1\n"
    assert_includes out, "source #{intercom.id} #{intercom.name}: backfilled=1 classified=0 failed=0 pending=1\n"
    assert_not_includes out, sources(:slack_community).name
    assert_includes out, "unfinished ClassifyMessageJob jobs: 2\n"
  ensure
    SolidQueue::Job.delete_all if SolidQueue::Job.table_exists?
  end

  test "backfill:status prints zero unfinished jobs when no backfilled messages exist" do
    SolidQueue::Job.delete_all

    out, = capture_io { Rake::Task["backfill:status"].invoke }

    assert_equal "unfinished ClassifyMessageJob jobs: 0\n", out
  ensure
    SolidQueue::Job.delete_all if SolidQueue::Job.table_exists?
  end

  private

  def build_stats(source, fetched:, created:, duplicates:, error: nil)
    Backfill::Stats.new(source).tap do |stats|
      stats.fetched = fetched
      stats.created = created
      stats.duplicates = duplicates
      stats.error = error
    end
  end

  def create_message(item, source, **attributes)
    item.messages.create!(
      source: source,
      external_id: "backfill-status-#{SecureRandom.hex(6)}",
      body: "Backfilled message",
      occurred_at: 1.hour.ago,
      **attributes
    )
  end

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
