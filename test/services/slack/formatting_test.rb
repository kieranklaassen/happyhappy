require "test_helper"

class Slack::FormattingTest < ActiveSupport::TestCase
  class Host
    include Slack::Formatting

    public :escape, :quote, :link, :item_url, :customer_handle, :percent, :section, :context
  end

  setup do
    @fmt = Host.new
  end

  test "escape encodes Slack control characters and coerces nil and non-strings" do
    assert_equal "&amp; &lt;tag&gt; &lt;!channel&gt;", @fmt.escape("& <tag> <!channel>")
    assert_equal "", @fmt.escape(nil)
    assert_equal "42", @fmt.escape(42)
  end

  test "escape breaks channel, here, and everyone mentions case-insensitively without breaking longer handles" do
    assert_equal "@\u200Bchannel @\u200Bhere @\u200Beveryone", @fmt.escape("@channel @here @everyone")
    assert_equal "@\u200BCHANNEL @\u200BHere @\u200BEveryone", @fmt.escape("@CHANNEL @Here @Everyone")
    assert_equal "ping @\u200Bchannel! (@\u200Bhere)", @fmt.escape("ping @channel! (@here)")
    assert_equal "@channeling @herewego @everyones @cora_team", @fmt.escape("@channeling @herewego @everyones @cora_team")
  end

  test "quote squishes whitespace, escapes text, prefixes a blockquote, and truncates to the limit" do
    assert_equal "&gt; line one &amp; &lt;two&gt; @\u200Bhere", @fmt.quote("  line one\n\t  & <two> @here  ")
    assert_equal "&gt; ", @fmt.quote(nil)
    assert_equal "&gt; hello wor...", @fmt.quote("hello world from every", limit: 12)

    long_quote = @fmt.quote("a" * (Slack::Formatting::QUOTE_LIMIT + 100))
    assert_equal "&gt; #{"a" * (Slack::Formatting::QUOTE_LIMIT - 3)}...", long_quote
  end

  test "link escapes both the URL and the label" do
    assert_equal(
      "<https://example.com/search?a=1&amp;b=&lt;2&gt;|A &amp; B &lt;@\u200Bhere&gt;>",
      @fmt.link("https://example.com/search?a=1&b=<2>", "A & B <@here>")
    )
  end

  test "item_url defaults to localhost and strips a trailing slash from PUBLIC_BASE_URL" do
    item = items(:angry_slack)

    with_env("PUBLIC_BASE_URL", nil) do
      assert_equal "http://localhost:3000/items/#{item.id}", @fmt.item_url(item)
    end

    with_env("PUBLIC_BASE_URL", "https://happyhappy.every.to") do
      assert_equal "https://happyhappy.every.to/items/#{item.id}", @fmt.item_url(item)
    end

    with_env("PUBLIC_BASE_URL", "https://happyhappy.every.to/") do
      assert_equal "https://happyhappy.every.to/items/#{item.id}", @fmt.item_url(item)
    end
  end

  test "customer_handle falls back from handle to email to name to unknown customer" do
    assert_equal "ana_handle", @fmt.customer_handle(Item.new(author_handle: "ana_handle", author_email: "ana@example.com", author_name: "Ana"))
    assert_equal "ana@example.com", @fmt.customer_handle(Item.new(author_handle: "   ", author_email: "ana@example.com", author_name: "Ana"))
    assert_equal "Ana", @fmt.customer_handle(Item.new(author_handle: nil, author_email: "", author_name: "Ana"))
    assert_equal "unknown customer", @fmt.customer_handle(Item.new(author_handle: nil, author_email: "  ", author_name: ""))
  end

  test "percent rounds probabilities to whole percentages" do
    assert_equal "86%", @fmt.percent(0.856)
    assert_equal "85%", @fmt.percent(0.854)
    assert_equal "0%", @fmt.percent(0)
    assert_equal "0%", @fmt.percent(nil)
    assert_equal "100%", @fmt.percent(1)
    assert_equal "13%", @fmt.percent("0.125")
  end

  test "section and context build Block Kit hashes and truncate at SECTION_LIMIT" do
    assert_equal(
      { type: "section", text: { type: "mrkdwn", text: "Hello *world*" } },
      @fmt.section("Hello *world*")
    )
    assert_equal(
      { type: "context", elements: [ { type: "mrkdwn", text: "Footer note" } ] },
      @fmt.context("Footer note")
    )

    oversized = "x" * (Slack::Formatting::SECTION_LIMIT + 50)
    expected = "#{"x" * (Slack::Formatting::SECTION_LIMIT - 3)}..."

    assert_equal expected, @fmt.section(oversized).dig(:text, :text)
    assert_equal expected, @fmt.context(oversized)[:elements].sole[:text]
  end

  private

  def with_env(key, value)
    had_key = ENV.key?(key)
    previous = ENV[key]
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    had_key ? ENV[key] = previous : ENV.delete(key)
  end
end
