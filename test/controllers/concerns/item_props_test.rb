require "test_helper"

class ItemPropsTest < ActiveSupport::TestCase
  class Host
    include ItemProps

    public :item_rows, :author_label, :source_props, :product_props, :category_props
  end

  setup do
    @host = Host.new
  end

  test "author_label falls back from handle to name to email to unknown" do
    assert_equal "ana_handle", @host.author_label(
      Item.new(author_handle: "ana_handle", author_name: "Ana Name", author_email: "ana@example.com")
    )
    assert_equal "Ana Name", @host.author_label(
      Item.new(author_handle: "   ", author_name: "Ana Name", author_email: "ana@example.com")
    )
    assert_equal "ana@example.com", @host.author_label(
      Item.new(author_handle: nil, author_name: "", author_email: "ana@example.com")
    )
    assert_equal "unknown", @host.author_label(
      Item.new(author_handle: " ", author_name: nil, author_email: "")
    )
  end

  test "product_props handles nil, active, and retired products" do
    assert_nil @host.product_props(nil)

    active = products(:cora)
    assert_equal(
      { id: active.id, name: active.name, slug: active.slug, retired: false },
      @host.product_props(active)
    )

    retired = products(:lex)
    assert_equal(
      { id: retired.id, name: retired.name, slug: retired.slug, retired: true },
      @host.product_props(retired)
    )
  end

  test "category_props handles nil, active, and retired categories" do
    assert_nil @host.category_props(nil)

    active = categories(:bug)
    assert_equal(
      { id: active.id, name: active.name, retired: false },
      @host.category_props(active)
    )

    retired = categories(:pricing)
    assert_equal(
      { id: retired.id, name: retired.name, retired: true },
      @host.category_props(retired)
    )
  end

  test "source_props returns only id, name, and kind" do
    source = sources(:slack_community)
    props = @host.source_props(source)

    assert_equal %w[id name kind], props.keys
    assert_equal({ id: source.id, name: source.name, kind: source.kind }, props.symbolize_keys)
  end

  test "item_rows returns an empty array for an empty relation" do
    assert_equal [], @host.item_rows(Item.none)
  end

  test "item_rows squishes and truncates the latest customer message while ignoring newer team replies" do
    item = items(:angry_slack)
    long_customer_body = "  First   line\n\n#{"word " * 80}tail  "

    item.messages.create!(
      source: item.source,
      external_id: "item-props-customer-latest",
      body: long_customer_body,
      author_role: "customer",
      occurred_at: 10.minutes.ago
    )
    item.messages.create!(
      source: item.source,
      external_id: "item-props-team-newer",
      body: "Internal team reply that should not become the excerpt",
      author_role: "team",
      occurred_at: 1.minute.ago
    )

    row = @host.item_rows(Item.where(id: item.id)).sole

    assert_equal long_customer_body.squish.truncate(ItemProps::EXCERPT_LENGTH), row[:excerpt]
    assert_equal ItemProps::EXCERPT_LENGTH, row[:excerpt].length
    assert_not_includes row[:excerpt], "\n"
    assert_not_includes row[:excerpt], "  "
    assert_equal item.id, row[:id]
    assert_equal "ana_customer", row[:author]
    assert_equal({ id: item.product.id, name: item.product.name, slug: item.product.slug, retired: false }, row[:product])
    assert_equal({ id: item.category.id, name: item.category.name, retired: false }, row[:category])
    assert_equal({ id: item.source.id, name: item.source.name, kind: item.source.kind }, row[:source].symbolize_keys)
  end

  test "item_rows produces an empty excerpt when an item has no customer messages" do
    empty_item = Item.create!(
      source: sources(:slack_community),
      thread_key: "item-props-no-messages",
      status: "new",
      last_message_at: 1.hour.ago
    )
    team_only_item = Item.create!(
      source: sources(:slack_community),
      thread_key: "item-props-team-only",
      status: "new",
      last_message_at: 1.hour.ago
    )
    team_only_item.messages.create!(
      source: team_only_item.source,
      external_id: "item-props-team-only-msg",
      body: "Team note only",
      author_role: "team",
      occurred_at: 30.minutes.ago
    )

    rows = @host.item_rows(Item.where(id: [ empty_item.id, team_only_item.id ])).index_by { |row| row[:id] }

    assert_equal "", rows.fetch(empty_item.id)[:excerpt]
    assert_equal "", rows.fetch(team_only_item.id)[:excerpt]
  end
end
