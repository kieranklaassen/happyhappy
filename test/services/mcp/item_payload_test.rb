require "test_helper"

class Mcp::ItemPayloadTest < ActiveSupport::TestCase
  test "summaries preserves the relation order and returns an empty array for an empty relation" do
    ids = [ items(:praise_discord).id, items(:angry_slack).id, items(:claimed_intercom).id ]

    ascending = Mcp::ItemPayload.summaries(Item.where(id: ids).order(id: :asc))
    descending = Mcp::ItemPayload.summaries(Item.where(id: ids).order(id: :desc))

    assert_equal ids.sort, ascending.map { |entry| entry[:id] }
    assert_equal ids.sort.reverse, descending.map { |entry| entry[:id] }
    assert_equal [], Mcp::ItemPayload.summaries(Item.none)
  end

  test "summaries populates base fields, labels, actionability, and untrusted author and excerpt" do
    item = items(:claimed_intercom)
    item.update!(
      actionability: 0.92,
      actionability_band: "act_now",
      overdue: true,
      needs_review: true,
      product_human_set: true,
      sentiment_human_set: true
    )

    summary = Mcp::ItemPayload.summaries(Item.where(id: item.id)).sole

    assert_equal item.id, summary[:id]
    assert_equal "claimed", summary[:status]
    assert_equal(
      { id: item.source.id, name: item.source.name, kind: "intercom" },
      summary[:source]
    )
    assert_equal item.permalink, summary[:permalink]
    assert_equal(
      { untrusted: true, handle: nil, name: "Bo Billing", email: "bo@example.com" },
      summary[:author]
    )
    assert_equal true, summary[:relevant]
    assert_equal true, summary[:needs_review]
    assert_equal true, summary[:overdue]
    assert_equal "Cursor", summary[:claimed_by]
    assert_equal item.last_message_at, summary[:last_message_at]
    assert_equal(
      {
        product: {
          value: { id: products(:cora).id, name: "Cora", slug: "cora" },
          probability: 0.7,
          human_set: true
        },
        category: {
          value: { id: categories(:billing).id, name: "billing" },
          probability: 0.9,
          human_set: false
        },
        sentiment: {
          value: "complaint",
          probability: 0.75,
          human_set: true
        },
        relevant: {
          value: true,
          probability: 0.95,
          human_set: false
        }
      },
      summary[:labels]
    )
    assert_equal 0.4, summary[:anger_probability]
    assert_equal({ score: 0.92, band: "act_now" }, summary[:actionability])
    assert_equal(
      { untrusted: true, text: messages(:claimed_intercom_first).body },
      summary[:excerpt]
    )
  end

  test "summaries handles nil product, category, claimed_by, and actionability" do
    item = items(:not_relevant_slack)
    summary = Mcp::ItemPayload.summaries(Item.where(id: item.id)).sole

    assert_nil summary[:claimed_by]
    assert_nil summary[:permalink]
    assert_equal false, summary[:relevant]
    assert_equal false, summary[:needs_review]
    assert_equal false, summary[:overdue]
    assert_equal({ value: nil, probability: nil, human_set: false }, summary[:labels][:product])
    assert_equal({ value: nil, probability: nil, human_set: false }, summary[:labels][:category])
    assert_equal({ value: false, probability: 0.08, human_set: false }, summary[:labels][:relevant])
    assert_equal({ score: nil, band: nil }, summary[:actionability])
  end

  test "summaries picks the latest customer message by occurred_at desc then id desc and ignores team replies" do
    item = create_item(thread_key: "mcp-payload-latest-customer")
    tied_at = 1.hour.ago.change(usec: 0)

    create_message(item:, body: "Earlier customer note", occurred_at: 2.hours.ago, author_role: :customer)
    create_message(item:, body: "First tied customer note", occurred_at: tied_at, author_role: :customer)
    create_message(item:, body: "Second tied unknown-author note", occurred_at: tied_at, author_role: :unknown)
    create_message(item:, body: "Newest team reply that must be ignored", occurred_at: 5.minutes.ago, author_role: :team)

    summary = Mcp::ItemPayload.summaries(Item.where(id: item.id)).sole

    assert_equal(
      { untrusted: true, text: "Second tied unknown-author note" },
      summary[:excerpt]
    )
  end

  test "summaries returns an empty untrusted excerpt when an item has no customer messages" do
    empty_item = create_item(thread_key: "mcp-payload-no-messages")
    team_only_item = create_item(thread_key: "mcp-payload-team-only")
    create_message(item: team_only_item, body: "Internal team update only", occurred_at: 10.minutes.ago, author_role: :team)

    summaries = Mcp::ItemPayload.summaries(Item.where(id: [ empty_item.id, team_only_item.id ]).order(:id))

    assert_equal(
      [ { untrusted: true, text: "" }, { untrusted: true, text: "" } ],
      summaries.map { |entry| entry[:excerpt] }
    )
  end

  test "summaries squishes whitespace and truncates excerpts at EXCERPT_LENGTH" do
    squish_item = create_item(thread_key: "mcp-payload-squish")
    create_message(item: squish_item, body: "  Line one\n\n\tline   two  \r\n line three  ", occurred_at: 20.minutes.ago, author_role: :customer)

    long_item = create_item(thread_key: "mcp-payload-truncate")
    create_message(item: long_item, body: "  #{'a' * 300}\n  ignored tail", occurred_at: 10.minutes.ago, author_role: :customer)

    summaries = Mcp::ItemPayload.summaries(Item.where(id: [ squish_item.id, long_item.id ]).order(:id))

    assert_equal({ untrusted: true, text: "Line one line two line three" }, summaries.first[:excerpt])
    assert_equal true, summaries.second[:excerpt][:untrusted]
    assert_equal 280, summaries.second[:excerpt][:text].length
    assert_equal "#{'a' * 277}...", summaries.second[:excerpt][:text]
  end

  test "detail includes base fields, claim and report timestamps, untrusted messages, and timeline actors" do
    claimed_at = 3.hours.ago.change(usec: 0)
    reported_at = 1.hour.ago.change(usec: 0)
    item = create_item(
      thread_key: "mcp-payload-detail",
      status: "claimed",
      claimed_by_agent: agents(:cursor),
      claimed_at: claimed_at,
      last_reported_at: reported_at,
      product: products(:cora),
      category: categories(:bug),
      sentiment: "complaint",
      product_probability: 0.91,
      category_probability: 0.84,
      sentiment_probability: 0.77,
      relevance_probability: 0.96,
      anger_probability: 0.63,
      actionability: 0.72,
      actionability_band: "should_reply"
    )

    first_message = create_message(
      item:,
      body: "First customer report",
      occurred_at: 4.hours.ago.change(usec: 0),
      anger_probability: 0.63,
      author_role: :customer
    )
    second_message = create_message(
      item:,
      body: "",
      occurred_at: 2.hours.ago.change(usec: 0),
      anger_probability: nil,
      author_role: :team
    )

    system_event = item.events.create!(kind: :arrived, data: { "source_id" => item.source_id }, created_at: 4.hours.ago.change(usec: 0))
    agent_event = item.events.create!(kind: :claimed, actor: agents(:cursor), data: {}, created_at: 3.hours.ago.change(usec: 0))
    named_user_event = item.events.create!(kind: :corrected, actor: users(:every_ana), data: { "label" => "product" }, created_at: 2.hours.ago.change(usec: 0))
    unnamed_user_event = item.events.create!(kind: :status_changed, actor: users(:one), data: { "from" => "new", "to" => "claimed" }, created_at: 1.hour.ago.change(usec: 0))

    payload = Mcp::ItemPayload.detail(item.reload)

    assert_not payload.key?(:excerpt)
    assert_equal item.id, payload[:id]
    assert_equal "claimed", payload[:status]
    assert_equal "Cursor", payload[:claimed_by]
    assert_equal claimed_at, payload[:claimed_at]
    assert_equal reported_at, payload[:last_reported_at]
    assert_equal({ untrusted: true, handle: "detail_user", name: "Detail User", email: "detail@example.com" }, payload[:author])
    assert_equal({ score: 0.72, band: "should_reply" }, payload[:actionability])

    assert_equal(
      [
        {
          id: first_message.id,
          occurred_at: first_message.occurred_at,
          anger_probability: 0.63,
          body: { untrusted: true, text: "First customer report" }
        },
        {
          id: second_message.id,
          occurred_at: second_message.occurred_at,
          anger_probability: nil,
          body: { untrusted: true, text: "" }
        }
      ],
      payload[:messages]
    )

    assert_equal(
      [
        {
          kind: "arrived",
          actor: { type: nil, name: "happyhappy" },
          data: { "source_id" => item.source_id },
          created_at: system_event.created_at
        },
        {
          kind: "claimed",
          actor: { type: "Agent", name: "Cursor" },
          data: {},
          created_at: agent_event.created_at
        },
        {
          kind: "corrected",
          actor: { type: "User", name: "Ana Every" },
          data: { "label" => "product" },
          created_at: named_user_event.created_at
        },
        {
          kind: "status_changed",
          actor: { type: "User", name: "one@example.com" },
          data: { "from" => "new", "to" => "claimed" },
          created_at: unnamed_user_event.created_at
        }
      ],
      payload[:timeline]
    )
  end

  private

  def create_item(**overrides)
    Item.create!({
      source: sources(:slack_community),
      source_kind: "slack",
      author_handle: "detail_user",
      author_name: "Detail User",
      author_email: "detail@example.com",
      permalink: "https://every-community.slack.com/archives/C0COMMUNITY/p999",
      last_message_at: 1.hour.ago.change(usec: 0)
    }.merge(overrides))
  end

  def create_message(item:, body:, occurred_at:, author_role:, anger_probability: nil)
    @message_seq = (@message_seq || 0) + 1
    item.messages.create!(
      source: item.source,
      external_id: "mcp-payload-msg-#{item.id}-#{@message_seq}",
      body: body,
      occurred_at: occurred_at,
      author_role: author_role,
      anger_probability: anger_probability
    )
  end
end
