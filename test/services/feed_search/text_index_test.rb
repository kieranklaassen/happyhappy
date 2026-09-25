require "test_helper"

class FeedSearch::TextIndexTest < ActiveSupport::TestCase
  include TrufflerHelper

  setup { FeedSearch::TextIndex.rebuild }

  def matching(*tokens)
    FeedSearch::TextIndex.matching(Item.all, tokens).ids
  end

  test "every token must match, each as a prefix, over message bodies and authors" do
    assert_equal [ items(:claimed_intercom).id ], matching("charged", "twice")
    assert_equal [ items(:claimed_intercom).id ], matching("refu")
    assert_equal [ items(:claimed_intercom).id ], matching("bo@example")
    assert_equal [ items(:angry_slack).id ], matching("ana_customer")
    assert_empty matching("charged", "lunch")
  end

  test "stemming and case fold: refunds finds refund" do
    assert_equal [ items(:claimed_intercom).id ], matching("REFUNDS")
  end

  test "punctuation and FTS syntax in a query are plain text" do
    assert_equal [ items(:claimed_intercom).id ], matching(%(charged"), "twice*)")
    assert_empty matching("charged", "NEAR(")
    assert_nil FeedSearch::TextIndex.matching(Item.all, [ "()", "" ])
  end

  test "a new message, an edited author, and a destroyed item refresh the index after commit" do
    item = items(:praise_discord)
    item.messages.create!(source: item.source, external_id: "fts-1", body: "Where is the export button?", occurred_at: Time.current,
      raw_payload: {})
    assert_equal [ item.id ], matching("export")

    item.update!(author_name: "Quill Writer")
    assert_equal [ item.id ], matching("quill")

    item.destroy!
    assert_empty matching("export")
  end
end
