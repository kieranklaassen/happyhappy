require "test_helper"

class FeedSearchTest < ActiveSupport::TestCase
  include TrufflerHelper
  include ActiveJob::TestHelper

  setup do
    @user = users(:every_ana)
    index_items_for_search!
  end

  def angry_cora_fake(**options)
    truffler_fake(intents: { "anger" => "filter", "product" => "filter" }, options: { "product" => "cora" },
      tokens: { "angry" => "label_term", "cora" => "label_term" }, **options)
  end

  test "before the encoding lands, keystroke search ranks keyword hits and enqueues the encoding" do
    result = nil
    assert_enqueued_with(job: Truffler::Jobs::EncodeQueryJob) { result = FeedSearch.keystroke("charged twice", user: @user) }

    assert_equal :pending, result.encoding_status
    assert_equal [ items(:claimed_intercom).id ], result.records.map(&:id)
    assert_empty result.chips
  end

  test "an encoded query filters by the labels it names and shows them as chips, with no Jev call at keystroke" do
    fake = angry_cora_fake
    encode_query!("angry cora", user: @user)
    calls = fake.calls.size

    result = FeedSearch.keystroke("angry cora", user: @user)

    assert_equal :cached, result.encoding_status
    assert_equal [ items(:angry_slack).id ], result.records.map(&:id)
    assert_equal [ "anger", "product:cora" ], result.chips.pluck(:key).sort
    assert_equal calls, fake.calls.size
  end

  test "a new team reply flips the team_replied filter with no Jev call" do
    fake = truffler_fake(intents: { "team_replied" => "filter" }, tokens: { "replied" => "label_term" })
    encode_query!("replied", user: @user)
    item = items(:angry_slack)
    calls = fake.calls.size
    assert_not_includes FeedSearch.keystroke("replied", user: @user).records.map(&:id), item.id

    item.messages.create!(source: item.source, external_id: "team-reply-1", body: "On it, fixing today",
      occurred_at: Time.current, raw_payload: {}, author_role: "team")

    assert_includes FeedSearch.keystroke("replied", user: @user).records.map(&:id), item.id
    assert_equal calls, fake.calls.size
  end

  test "a time phrase becomes the first chip and a feed time filter" do
    result = FeedSearch.keystroke("cora last 3 hours", user: @user)

    assert_equal "cora", result.query
    assert_equal({ key: "time", label: "time", kind: "filter", name: "Last 3 hours" }, result.chips.first)
    assert_equal [ items(:angry_slack).id ], result.records.map(&:id)
  end

  test "removing a chip drops that label or the time filter" do
    angry_cora_fake
    encode_query!("angry cora", user: @user)

    no_anger = FeedSearch.keystroke("angry cora last 3 hours", user: @user, suppressed: [ "anger" ])
    no_time = FeedSearch.keystroke("cora last 3 hours", user: @user, suppressed: [ "time" ])

    assert_equal [ "time", "product:cora" ], no_anger.chips.pluck(:key)
    assert_equal [ items(:angry_slack).id, items(:claimed_intercom).id, items(:handled_email).id ].sort, no_time.records.map(&:id).sort
  end

  test "search stays inside the feed filters" do
    result = FeedSearch.keystroke("cora", user: @user, filters: { status: [ "claimed" ] })

    assert_equal [ items(:claimed_intercom).id ], result.records.map(&:id)
    assert_raises(ItemsQuery::InvalidFilter) { FeedSearch.keystroke("cora", user: @user, filters: { status: [ "lost" ] }) }
  end

  test "Smart search buckets the candidates for its searcher only, and a query change cancels it" do
    angry_cora_fake(labels: { "relevance" => 0.9 })
    encode_query!("angry cora", user: @user)

    run = perform_enqueued_jobs { FeedSearch.smart("angry cora", user: @user) }
    smart = FeedSearch.find_run(run.id, user: @user).to_h

    assert_equal [ items(:angry_slack).id.to_s ], smart[:buckets][:strong].map { |entry| entry[:id].to_s }
    assert_equal :expired, FeedSearch.find_run(run.id, user: users(:one)).status

    FeedSearch.cancel(user: @user)
    assert_equal :cancelled, FeedSearch.find_run(run.id, user: @user).status
  end

  test "Smart search needs words beyond a time phrase" do
    assert_nil FeedSearch.smart("this week", user: @user)
  end
end
