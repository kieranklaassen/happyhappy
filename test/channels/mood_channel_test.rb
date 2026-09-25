# frozen_string_literal: true

require "test_helper"

class MoodChannelTest < ActionCable::Channel::TestCase
  include ActionCable::TestHelper

  test "subscribing streams the mood pings" do
    stub_connection current_user: users(:one)

    subscribe

    assert subscription.confirmed?
    assert_has_stream MoodChannel::STREAM
  end

  test "a changed item pings open dashboards without customer data" do
    assert_broadcasts(MoodChannel::STREAM, 1) do
      items(:angry_slack).update!(anger_probability: 0.95)
    end

    payload = ActiveSupport::JSON.decode(broadcasts(MoodChannel::STREAM).last)
    assert_equal %w[changed_at backfill], payload.keys
    assert_equal false, payload["backfill"]
  end

  test "a live message pings as live when it arrives and when it is classified" do
    use_fake_classifier
    result = ingest(backfill: false)
    ClassifyMessageJob.perform_now(result.message)

    assert_equal [ false ], pings.map { |ping| ping["backfill"] }.uniq
  end

  test "backfilled history pings as backfill when it arrives and when it is classified" do
    use_fake_classifier
    result = ingest(backfill: true)
    ClassifyMessageJob.perform_now(result.message)

    assert_operator pings.size, :>=, 2
    assert_equal [ true ], pings.map { |ping| ping["backfill"] }.uniq
  end

  test "a rerun pings as backfill" do
    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("classifications:rerun")
    Rake::Task["classifications:rerun"].reenable
    use_fake_classifier(anger: 0.42)
    ENV["ITEM_IDS"] = items(:angry_slack).id.to_s

    assert_output(/rerun finished/) { Rake::Task["classifications:rerun"].invoke }

    assert_not_empty pings
    assert_equal [ true ], pings.map { |ping| ping["backfill"] }.uniq
  ensure
    ENV.delete("ITEM_IDS")
  end

  test "a broken cable never fails the item save" do
    ActionCable.server.define_singleton_method(:broadcast) { |*| raise "cable down" }

    assert_error_reported(RuntimeError) do
      assert items(:angry_slack).update!(anger_probability: 0.5)
    end
  ensure
    ActionCable.server.singleton_class.remove_method(:broadcast)
  end

  private

  def pings
    broadcasts(MoodChannel::STREAM).map { |payload| ActiveSupport::JSON.decode(payload) }
  end

  def ingest(backfill:)
    inbound = Items::InboundMessage.new(external_id: "ping-1", thread_key: "ping-thread", body: "Spiral lost my draft",
      author_handle: "writer", raw_payload: {})
    Items::Ingest.call(source: sources(:discord_spiral), inbound: inbound, backfill: backfill)
  end
end
