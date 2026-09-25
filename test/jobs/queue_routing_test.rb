require "test_helper"
require "erb"

class QueueRoutingTest < ActiveJob::TestCase
  WORKERS = YAML.load(ERB.new(File.read(Rails.root.join("config/queue.yml"))).result, aliases: true)
    .fetch("production").fetch("workers").freeze

  test "live work runs on the realtime queue" do
    assert_equal "realtime", ClassifyMessageJob.queue_name
    assert_equal "realtime", SlackEventJob.queue_name
    assert_equal "realtime", PostEscalationJob.queue_name
  end

  test "outbound webhook deliveries run on their own queue" do
    assert_equal "webhooks", WebhookDeliveryJob.queue_name
  end

  test "the realtime queue has a worker pool of its own with enough threads for TypeSafe's limit" do
    realtime = WORKERS.select { |worker| Array(worker["queues"]).include?("realtime") }

    assert_equal 1, realtime.size
    assert_equal [ "realtime" ], Array(realtime.sole["queues"])
    assert_equal 12, realtime.sole["threads"]
    assert_operator realtime.sole["polling_interval"], :<=, 0.05
  end

  test "the shared worker takes webhooks and default work before backfill" do
    shared = WORKERS.find { |worker| Array(worker["queues"]).include?("backfill") }

    assert_equal %w[webhooks default solid_queue_recurring backfill], shared["queues"]
  end

  test "every job's queue is served by a worker" do
    Rails.application.eager_load!
    served = WORKERS.flat_map { |worker| Array(worker["queues"]) }

    # Framework jobs with a computed queue (mailers, Active Storage) fall back to default.
    ActiveJob::Base.descendants.select { |job| job.name && job.queue_name.is_a?(String) }.each do |job|
      assert_includes served, job.queue_name, "#{job.name} runs on #{job.queue_name.inspect}, which no worker serves"
    end
  end

  test "the database pool covers the realtime worker's threads plus its poller and heartbeat" do
    pool = ActiveRecord::Base.connection_db_config.configuration_hash[:max_connections].to_i

    assert_operator pool, :>=, WORKERS.map { |worker| worker["threads"].to_i }.max + 2
  end
end
