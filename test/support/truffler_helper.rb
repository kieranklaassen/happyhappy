# Feed search in tests (U25). Truffler talks to a scripted fake instead of
# TypeSafe, and its cache is emptied before every test so encodings and Smart
# runs never leak between tests. Unscripted, the fake applies no label.
#
#   index_items_for_search!                                  # fixtures skip callbacks
#   Truffler.config.client.answer("intent__anger", "filter").answer("intent__product", "filter").answer("option__product", "cora")
#   encode_query!("angry cora", user: users(:every_ana))     # runs the encoding job against the fake
module TrufflerHelper
  def index_items_for_search!
    FeedSearch::TextIndex.rebuild
    Item.find_each(&:truffler_refresh_labels!)
  end

  # Runs the keystroke search once so it enqueues the encoding, then runs that job.
  def encode_query!(query, user:)
    FeedSearch.keystroke(query, user: user)
    key = Truffler::Search::EncodingCache.new.key(Item, Truffler::Search::Query.new(FeedSearch.prepare(query, []).first),
      tenant_key: nil, user_key: Truffler::Search::Keystroke.user_key(user))
    Truffler::Jobs::EncodeQueryJob.perform_now(key)
  end
end

class ActiveSupport::TestCase
  setup do
    Truffler.config.cache_store.clear
    Truffler.config.client = Truffler::Clients::Fake.new
  end
end
