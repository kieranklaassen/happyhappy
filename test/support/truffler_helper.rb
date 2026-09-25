# Feed search in tests (U25). Truffler talks to a scripted fake instead of
# TypeSafe (config/initializers/truffler.rb), and its cache is emptied before
# every test so encodings and Smart runs never leak between tests.
#
#   index_items_for_search!                                  # fixtures skip callbacks
#   fake = truffler_fake(intents: { "anger" => "filter", "product" => "filter" }, options: { "product" => "cora" },
#     tokens: { "angry" => "label_term", "cora" => "label_term" })
#   encode_query!("angry cora", user: users(:every_ana))     # runs the encoding job against the fake
module TrufflerHelper
  # Query encoding asks intent__<label>, option__<label>, and token__<position>;
  # unscripted, the fake would pick the first option (filter) for every label.
  def truffler_fake(intents: {}, options: {}, tokens: {}, labels: {})
    Truffler.config.client = Truffler::Clients::Fake.new do |tag, state, id|
      case tag
      when "intent" then intents.fetch(id.delete_prefix("intent__"), "ignore")
      when "option" then options.fetch(id.delete_prefix("option__"), "none")
      when "token" then tokens.fetch(state.fetch("tokens")[id.delete_prefix("token__").to_i], "keyword")
      else labels.fetch(id.split("__").last, 0.0)
      end
    end
  end

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

# A fresh test database is loaded after boot, when Item cached an empty column list.
unless Item.truffler_definition
  Item.reset_column_information
  Item.declare_truffler
end

class ActiveSupport::TestCase
  setup do
    Truffler.config.cache_store.clear
    Truffler.config.client = Truffler::Clients::Fake.new
  end
end
