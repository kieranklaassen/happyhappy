# Feed search (U25): the feed controller and the search_items agent tool both
# search through here, so people and agents get the same results for the same
# query and filters.
#
#   result = FeedSearch.keystroke("angry Cora billing this week", user: Current.user, filters: { status: "new" })
#   result.records   # ranked items, all inside ItemsQuery.new(**filters)
#   result.chips     # [{key:, label:, kind:, name:}], filters, boosts, then the time chip
#   result.relaxed_notice  # "Nothing matched Source: email; showing results without it." or nil
#
#   run = FeedSearch.smart("angry Cora billing", user: Current.user)   # on Enter
#   FeedSearch.find_run(run.id, user: Current.user).to_h                   # the smart prop
#
# Keystroke search makes no network call: it reads the query encoding from
# the cache and enqueues it on a miss (encoding_status :pending), so the next
# keystroke or reload ranks by intent. Truffler reads a time phrase ("this
# week") locally into a `last_message_at` window and a `kind: :time` chip.
# Suppressed chip keys drop a label or, with "time", the time window.
module FeedSearch
  SURFACE = :feed
  MAX_QUERY_LENGTH = 200
  MAX_SUPPRESSED = 20
  ENCODING_POLL = 0.1

  # relaxed_labels: filters truffler dropped because nothing matched with them
  # (their chips carry `relaxed: true` and still rank matching items first).
  Result = Data.define(:query, :records, :chips, :relaxed_labels, :invite_row, :encoding_status, :explicit_action, :watermark) do
    def relaxed_notice
      names = chips.select { |chip| chip[:relaxed] }.pluck(:name)
      return if names.empty?

      "Nothing matched #{names.to_sentence(two_words_connector: ' or ', last_word_connector: ', or ')}; " \
        "showing results without #{names.one? ? 'it' : 'them'}."
    end
  end

  module_function

  # wait: seconds to wait for a pending query encoding, for callers such as
  # agents that cannot come back on the next keystroke.
  def keystroke(query, user:, filters: {}, suppressed: [], limit: Truffler::Search::Keystroke::DEFAULT_LIMIT, wait: 0)
    text, suppressed = prepare(query, suppressed)
    scope = scope(filters)
    result = Item.truffler(text, scope: scope, user: user, suppressed: suppressed, surface: SURFACE, limit: limit)
    deadline = monotonic + wait.to_f
    while result.encoding_status == :pending && monotonic < deadline
      sleep ENCODING_POLL
      result = Item.truffler(text, scope: scope, user: user, suppressed: suppressed, surface: SURFACE, limit: limit)
    end

    Result.new(query: text, records: result.records, chips: result.chips, relaxed_labels: result.relaxed_labels, invite_row: result.invite_row,
      encoding_status: result.encoding_status, explicit_action: result.explicit_action, watermark: result.watermark)
  end

  # Starts a Smart run (Jev reranks the top candidates into Strong, Possible,
  # and Unlikely) and supersedes the searcher's previous one. Nil for a query
  # with nothing left to rerank on.
  def smart(query, user:, filters: {}, suppressed: [])
    text, suppressed = prepare(query, suppressed)
    return if Truffler::Search::Query.new(text).search_tokens.empty?

    Item.jev_smart_search(text, scope: scope(filters), user: user, surface: SURFACE, suppressed: suppressed)
  end

  # The searcher's own run, or an expired one for anyone else's id.
  def find_run(run_id, user:)
    Truffler::SmartSearch.find(run_id.to_s, user: user, tenant: nil)
  end

  # Ends the searcher's in-flight run, as when the query or a chip changes.
  def cancel(user:)
    Item.jev_cancel_smart_search(user: user, surface: SURFACE)
  end

  def prepare(query, suppressed)
    suppressed = Array(suppressed).map(&:to_s).compact_blank.first(MAX_SUPPRESSED)
    [ query.to_s.first(MAX_QUERY_LENGTH).squish, suppressed ]
  end

  def scope(filters)
    ItemsQuery.new(**filters.to_h.symbolize_keys).call
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
