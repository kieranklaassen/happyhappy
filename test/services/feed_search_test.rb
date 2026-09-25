require "test_helper"

class FeedSearchTest < ActiveSupport::TestCase
  include TrufflerHelper
  include ActiveJob::TestHelper

  setup do
    @user = users(:every_ana)
    index_items_for_search!
  end

  def angry_cora_fake
    Truffler.config.client.answer("intent__anger", "filter").answer("intent__product", "filter").answer("option__product", "cora")
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

  test "angry Cora billing this week filters on the three labels and the week, with no word required in the text" do
    Truffler.config.client.answer("intent__anger", "filter").answer("intent__product", "filter").answer("option__product", "cora")
      .answer("intent__category", "filter").answer("option__category", "billing")
    item = items(:claimed_intercom)
    item.update_columns(anger_probability: 0.9, last_message_at: Time.current)
    item.truffler_refresh_labels!
    encode_query!("angry Cora billing this week", user: @user)

    result = FeedSearch.keystroke("angry Cora billing this week", user: @user)

    assert_equal [ item.id ], result.records.map(&:id)
    assert_equal [ "anger", "category:billing", "product:cora", "time" ], result.chips.pluck(:key).sort
  end

  test "needs action now filters on needs_action, with no word required in the text" do
    Truffler.config.client.answer("intent__needs_action", "filter")
    item = items(:handled_email)
    item.update_columns(actionability: 0.7)
    item.truffler_refresh_labels!
    encode_query!("needs action now", user: @user)

    result = FeedSearch.keystroke("needs action now", user: @user)

    assert_equal [ item.id ], result.records.map(&:id)
    assert_equal [ "needs_action" ], result.chips.pluck(:key)
  end

  test "the none product option is filterable" do
    Truffler.config.client.answer("intent__product", "filter").answer("option__product", Item::Searchable::NO_PRODUCT)
    item = items(:needs_review_x)
    item.update_columns(product_id: nil)
    item.truffler_refresh_labels!
    encode_query!("not about a product", user: @user)

    result = FeedSearch.keystroke("not about a product", user: @user)

    assert_equal [ "product:#{Item::Searchable::NO_PRODUCT}" ], result.chips.pluck(:key)
    assert_equal [ item.id ], result.records.map(&:id)
  end

  test "a new team reply flips the team_replied filter with no Jev call" do
    fake = Truffler.config.client.answer("intent__team_replied", "filter")
    encode_query!("replied", user: @user)
    item = items(:angry_slack)
    calls = fake.calls.size
    assert_not_includes FeedSearch.keystroke("replied", user: @user).records.map(&:id), item.id

    item.messages.create!(source: item.source, external_id: "team-reply-1", body: "On it, fixing today",
      occurred_at: Time.current, raw_payload: {}, author_role: "team")

    assert_includes FeedSearch.keystroke("replied", user: @user).records.map(&:id), item.id
    assert_equal calls, fake.calls.size
  end

  test "a time phrase becomes a time chip and limits results to when the item last heard from someone" do
    result = FeedSearch.keystroke("cora last 3 hours", user: @user)

    assert_equal "cora last 3 hours", result.query
    assert_equal [ { key: "time", label: "time", kind: :time, name: "Last 3 hours" } ], result.chips
    assert_equal [ items(:angry_slack).id ], result.records.map(&:id)
  end

  test "past week and past month are rolling windows that end now" do
    items(:handled_email).update_columns(last_message_at: 10.days.ago)
    week = FeedSearch.keystroke("cora past week", user: @user)
    month = FeedSearch.keystroke("cora past month", user: @user)

    assert_equal [ "Past week" ], week.chips.pluck(:name)
    assert_equal [ items(:angry_slack).id, items(:claimed_intercom).id ].sort, week.records.map(&:id).sort
    assert_equal [ "Past month" ], month.chips.pluck(:name)
    assert_equal [ items(:angry_slack).id, items(:claimed_intercom).id, items(:handled_email).id ].sort, month.records.map(&:id).sort
  end

  test "removing a chip drops that label or the time filter" do
    angry_cora_fake
    encode_query!("angry cora", user: @user)

    encode_query!("angry cora last 3 hours", user: @user)

    no_anger = FeedSearch.keystroke("angry cora last 3 hours", user: @user, suppressed: [ "anger" ])
    no_time = FeedSearch.keystroke("cora last 3 hours", user: @user, suppressed: [ "time" ])

    assert_equal [ "product:cora", "time" ], no_anger.chips.pluck(:key)
    assert_equal [ items(:angry_slack).id, items(:claimed_intercom).id, items(:handled_email).id ].sort, no_time.records.map(&:id).sort
  end

  test "search stays inside the feed filters" do
    result = FeedSearch.keystroke("cora", user: @user, filters: { status: [ "claimed" ] })

    assert_equal [ items(:claimed_intercom).id ], result.records.map(&:id)
    assert_raises(ItemsQuery::InvalidFilter) { FeedSearch.keystroke("cora", user: @user, filters: { status: [ "lost" ] }) }
  end

  test "Smart search buckets the candidates for its searcher only, and a query change cancels it" do
    angry_cora_fake.answer(:relevance, 0.9)
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
