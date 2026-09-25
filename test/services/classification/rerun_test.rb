require "test_helper"

class Classification::RerunTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class FakeMembers
    attr_reader :lookups

    def initialize(roles)
      @roles = roles
      @lookups = 0
    end

    def with_member(payload, _guild_id)
      @lookups += 1
      roles = @roles[payload.dig("author", "id")]
      roles ? payload.merge("member" => { "roles" => roles }) : payload
    end
  end

  setup do
    Setting.current.update!(team_discord_role_ids: [ "797" ])
    @item = Item.create!(source: sources(:discord_spiral), thread_key: "rerun-#{SecureRandom.hex(4)}",
      author_handle: "kieran_2", author_name: "Kieran", product: products(:spiral), last_message_at: 1.hour.ago,
      status_changed_at: 2.hours.ago)
    @announcement = add_message("staff", "Spiral 2 ships today!", 50.minutes.ago)
    @complaint = add_message("customer", "Spiral lost my draft. Furious.", 40.minutes.ago)
    @thanks = add_message("customer", "Got it back, thank you!", 30.minutes.ago)
    @members = FakeMembers.new("staff" => [ "797" ], "customer" => [ "1" ])
  end

  test "sets author roles, reclassifies in thread order, and rolls the item up to the customer's current state" do
    fake = FakeClassifier.new(lambda { |message|
      case message.body
      when /Furious/ then FakeClassifier.answers(product: "spiral", sentiment: "complaint", anger: 0.9)
      when /thank you/ then FakeClassifier.answers(product: "spiral", sentiment: "relieved", anger: 0.05)
      else FakeClassifier.answers(product: "spiral", sentiment: "praise", anger: 0.0)
      end
    })

    stats = rerun(fake)

    assert_equal [ @announcement, @complaint, @thanks ], fake.calls
    assert_equal({ items: 1, messages: 3, reclassified: 3 }, stats.slice(:items, :messages, :reclassified))
    assert @announcement.reload.author_team?
    assert @complaint.reload.author_customer?
    @item.reload
    assert @item.relieved?
    assert_in_delta 0.05, @item.anger_probability
    assert_equal "customer", @item.author_handle
    assert_equal @thanks.occurred_at.to_i, @item.last_message_at.to_i
  end

  test "is idempotent: a second run reclassifies nothing" do
    rerun(FakeClassifier.new)
    fake = FakeClassifier.new

    stats = rerun(fake)

    assert_empty fake.calls
    assert_equal 3, stats[:skipped]
  end

  test "never escalates or delivers webhooks, and keeps labels a human set" do
    WebhookEndpoint.create!(name: "all", url: "https://hooks.example.com/in", events: %w[item.classified])
    products(:spiral).update!(slack_channel_id: "C0SPIRAL")
    @item.update!(sentiment: "praise", sentiment_human_set: true)

    assert_no_enqueued_jobs(only: [ PostEscalationJob, WebhookDeliveryJob ]) do
      rerun(FakeClassifier.new(FakeClassifier.answers(product: "spiral", sentiment: "complaint", anger: 0.99)))
    end

    assert @item.reload.praise?
    assert_empty @item.escalations
    assert @item.events.classified.all? { |event| event.data["backfill"] && event.data["reclassified"] }
  end

  test "records a provider failure on the message and keeps going" do
    fake = FakeClassifier.new.fail_with(RubyLLM::ServerError.new("boom"))

    stats = rerun(fake)

    assert_equal 3, stats[:failed]
    assert_match "boom", @thanks.reload.classification_error
  end

  private

  def rerun(classifier)
    Classification::Rerun.new(items: Item.where(id: @item.id), classifier: classifier, discord_members: @members).call
  end

  def add_message(author_id, body, at)
    @item.messages.create!(source: @item.source, external_id: SecureRandom.hex(6), body: body, occurred_at: at,
      created_at: 3.hours.ago, raw_payload: { "guild_id" => "1", "author" => { "id" => author_id, "username" => author_id } })
  end
end
