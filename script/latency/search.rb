# frozen_string_literal: true

# Feed search latency harness (run it through script/latency/search.sh, which
# points every database at tmp/latency-search). Seeds a production-sized feed,
# then times:
#
#   keystroke   FeedSearch.keystroke plus the feed rows the controller renders,
#               before the query encoding lands (keyword only) and after
#   smart       Enter -> first Smart search bucket readable by the page's
#               `smart` reload, with the real Solid Queue supervisor working
#               SmartSearchJob and RerankChunkJob from config/queue.yml
#
# Jev is a stub sleeping 300 to 900 ms per call (seeded) unless --live, which
# sends the example queries to TypeSafe (TYPESAFE_API_KEY must be in the
# environment; source it in the same command and never print it).
unless ENV["SEARCH_LATENCY_HARNESS"] == "1" && Rails.env.production? &&
    ActiveRecord::Base.connection_db_config.database.to_s.include?("tmp/latency-search")
  abort "script/latency/search.rb only runs through script/latency/search.sh"
end

require "optparse"
require "zlib"

OPTIONS = { items: 20_000, repeat: 40, smart: 5, seed: 25, live: false }
OptionParser.new do |parser|
  parser.on("--items N", Integer, "feed items to seed (20000)") { |value| OPTIONS[:items] = value }
  parser.on("--repeat N", Integer, "timed keystrokes per query and state (40)") { |value| OPTIONS[:repeat] = value }
  parser.on("--smart N", Integer, "Smart searches per example query (5)") { |value| OPTIONS[:smart] = value }
  parser.on("--seed N", Integer, "data and stub latency seed (25)") { |value| OPTIONS[:seed] = value }
  parser.on("--live", "encode and rerank the example queries with TypeSafe") { OPTIONS[:live] = true }
end.parse!(ARGV)

EXAMPLES = [ "angry Cora billing this week", "needs action now", "praise for Thesis" ].freeze
KEYSTROKES = [ *EXAMPLES, "charged twice", "refund", "sparkle deleted", "exp", "cora", "angry cora billing" ].freeze
JEV_LATENCY = (0.3..0.9)

module SearchLatency
  module_function

  PRODUCTS = {
    "cora" => "Cora", "spiral" => "Spiral", "sparkle" => "Sparkle", "monologue" => "Monologue", "thesis" => "Thesis"
  }.freeze
  CATEGORIES = %w[billing bug praise question feature_request cancellation].freeze
  PHRASES = {
    "billing" => [ "I was charged twice this month", "please refund my annual plan", "where is my invoice", "the price went up again" ],
    "bug" => [ "deleted half my inbox", "lost my draft when I exported", "keeps crashing on launch", "moved my files into the wrong folder" ],
    "praise" => [ "saved me an hour today, thank you", "love the new update", "best tool I pay for", "my whole team uses it now" ],
    "question" => [ "how do I connect a second account", "does it work offline", "can I share with my team", "is there a keyboard shortcut" ],
    "feature_request" => [ "please add dark mode", "I wish it had an API", "would love a Windows version", "add Dutch dictation" ],
    "cancellation" => [ "I am cancelling my subscription", "switching to another tool", "not worth the money anymore", "how do I close my account" ]
  }.freeze
  SENTIMENT = { "billing" => "complaint", "bug" => "complaint", "praise" => "praise", "question" => "question",
    "feature_request" => "neutral", "cancellation" => "complaint" }.freeze

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def time
    started = now
    yield
    now - started
  end

  def percentile(values, fraction)
    sorted = values.sort
    sorted[((sorted.size - 1) * fraction).round]
  end

  def summary(values)
    return "no samples" if values.empty?

    ms = values.map { |value| value * 1000 }
    format("p50 %6.1f ms  p95 %6.1f ms  max %6.1f ms  (n=%d)", percentile(ms, 0.5), percentile(ms, 0.95), ms.max, ms.size)
  end

  def seed!(count, random)
    now = Time.current
    sources = %w[slack discord intercom email x].to_h do |kind|
      [ kind, Source.find_or_create_by!(kind: kind, selector: "bench-#{kind}") { |source| source.name = "Bench #{kind}" } ]
    end
    products = PRODUCTS.map do |slug, name|
      Product.find_by(slug: slug) || Product.create!(slug: slug, name: name, description: "#{name} demo product.")
    end
    categories = CATEGORIES.to_h { |name| [ name, Category.find_or_create_by!(name: name) { |category| category.description = name.humanize } ] }

    count.times.each_slice(1_000) do |slice|
      items = slice.map do |index|
        category = CATEGORIES.sample(random: random)
        kind = sources.keys.sample(random: random)
        anger = category == "praise" ? random.rand(0.0..0.1) : random.rand(0.0..1.0)
        actionability = category == "praise" ? random.rand(0.0..0.3) : random.rand(0.0..1.0)
        at = now - random.rand(0..(90 * 24 * 3600))
        { source_id: sources[kind].id, source_kind: kind, thread_key: "bench-#{index}", author_handle: "person#{index % 4_000}",
          product_id: products.sample(random: random).id, category_id: categories[category].id, sentiment: SENTIMENT[category],
          sentiment_probability: 0.8, product_probability: 0.8, category_probability: 0.8, relevance_probability: 0.95,
          anger_probability: anger.round(3), actionability: actionability.round(3),
          actionability_band: Actionability.band(score: actionability, relevant: true), status: "new", status_changed_at: at,
          last_message_at: at, created_at: at, updated_at: at }
      end
      ids = Item.insert_all!(items, returning: %w[id product_id category_id last_message_at]).rows
      messages = ids.flat_map do |id, product_id, category_id, at|
        product = products.find { |candidate| candidate.id == product_id }.name
        category = categories.key(categories.values.find { |candidate| candidate.id == category_id })
        Array.new(random.rand(1..3)) do |position|
          body = "#{product}: #{PHRASES[category].sample(random: random)}. #{PHRASES.values.flatten.sample(random: random)}."
          { item_id: id, source_id: sources.values.first.id, external_id: "bench-#{id}-#{position}", body: body,
            author_role: position.zero? ? "customer" : %w[customer team].sample(random: random), occurred_at: at, raw_payload: {},
            created_at: at, updated_at: at }
        end
      end
      Message.insert_all!(messages)
    end

    FeedSearch::TextIndex.rebuild
    keys = Item.truffler_definition.supplied_labels.map(&:key)
    Item.includes(:product, :category).in_batches(of: 500) do |batch|
      Truffler::Labeling::Supplied.new(Item).write(batch.map { |item| [ item, keys ] }, tenant_key: nil)
    end
  end

  RULES = [
    [ %w[angry furious], { "anger" => "filter" }, {} ],
    [ %w[billing refund charged invoice], { "category" => "filter" }, { "category" => "billing" } ],
    [ %w[praise love], { "sentiment" => "filter" }, { "sentiment" => "praise" } ],
    [ %w[needs action now], { "needs_action" => "filter" }, {} ],
    [ %w[deleted], { "category" => "boost" }, { "category" => "bug" } ]
  ].freeze

  # Reads a query the way Jev tends to, from the words it contains.
  def read(query)
    words = query.downcase.scan(/\p{Alnum}+/)
    intents = {}
    options = {}
    terms = []
    RULES.each do |triggers, rule_intents, rule_options|
      hit = words & triggers
      next if hit.empty?

      intents.merge!(rule_intents)
      options.merge!(rule_options)
      terms.concat(hit)
    end
    product = words.find { |word| PRODUCTS.key?(word) }
    if product
      intents["product"] = "filter"
      options["product"] = product
      terms << product
    end
    [ intents, options, terms ]
  end

  def stub_client(seed)
    Truffler::Clients::Fake.new do |tag, state, id|
      intents, options, terms = read(state["query"].to_s)
      case tag
      when "intent" then intents.fetch(id.delete_prefix("intent__"), "ignore")
      when "option" then options.fetch(id.delete_prefix("option__"), "none")
      when "token"
        word = state.fetch("tokens")[id.delete_prefix("token__").to_i]
        terms.include?(word) ? "label_term" : (%w[for this the a].include?(word) ? "filler" : "keyword")
      else
        text = state.dig("candidates", tag).to_s.downcase
        words = state["query"].to_s.downcase.scan(/\p{Alnum}+/)
        (words.count { |word| text.include?(word) }.fdiv([ words.size, 1 ].max) + Random.new(seed + Zlib.crc32(text)).rand(-0.1..0.1)).clamp(0, 1)
      end
    end.tap do |client|
      client.define_singleton_method(:perform) do |**options|
        sleep Random.new(seed + Zlib.crc32(options[:state].to_json)).rand(JEV_LATENCY)
        super(**options)
      end
    end
  end

  def encode!(query, user)
    FeedSearch.keystroke(query, user: user)
    text = FeedSearch.prepare(query, []).first
    key = Truffler::Search::EncodingCache.new.key(Item, Truffler::Search::Query.new(text), tenant_key: nil,
      user_key: Truffler::Search::Keystroke.user_key(user))
    Truffler::Jobs::EncodeQueryJob.perform_now(key)
  end
end

class Rows
  include ItemProps
  public :item_rows
end

random = Random.new(OPTIONS[:seed])
user = User.create!(email_address: "bench@every.to", name: "Bench")
Truffler.config.client = SearchLatency.stub_client(OPTIONS[:seed]) unless OPTIONS[:live]

started = Time.current
SearchLatency.seed!(OPTIONS[:items], random)
puts "Seeded #{Item.count} items, #{Message.count} messages, #{Truffler::Records::Label.count} labels in " \
  "#{(Time.current - started).round(1)} s#{' (live TypeSafe)' if OPTIONS[:live]}"

rows = Rows.new
keystroke = ->(query) do
  result = FeedSearch.keystroke(query, user: user)
  rows.item_rows(Item.where(id: result.records.map(&:id)))
  result
end
KEYSTROKES.each { |query| keystroke.call(query) } # warm the statement cache

pending_times = []
KEYSTROKES.each do |query|
  Truffler.config.cache_store.clear
  OPTIONS[:repeat].times do
    pending_times << SearchLatency.time { keystroke.call(query) }
  end
end

EXAMPLES.each { |query| SearchLatency.encode!(query, user) }
(KEYSTROKES - EXAMPLES).each { |query| SearchLatency.encode!(query, user) }
cached_times = []
counts = {}
KEYSTROKES.each do |query|
  OPTIONS[:repeat].times do
    result = nil
    cached_times << SearchLatency.time { result = keystroke.call(query) }
    counts[query] = [ result.encoding_status, result.records.size, result.chips.pluck(:name) ]
  end
end

puts
puts "Keystroke (search + feed rows, #{Item.count} items)"
puts "  encoding pending  #{SearchLatency.summary(pending_times)}"
puts "  encoding cached   #{SearchLatency.summary(cached_times)}"
EXAMPLES.each do |query|
  status, size, chips = counts[query]
  puts "  #{query.inspect}: #{status}, #{size} results, chips #{chips.inspect}"
end

supervisor = fork { SolidQueue::Supervisor.start }
at_exit { Process.kill("TERM", supervisor) rescue nil }
workers = SolidQueue::Configuration.new(mode: :fork).configured_processes.count { |process| process.kind == :worker }
deadline = 30.seconds.from_now
sleep 0.2 until SolidQueue::Process.where(kind: "Worker").count >= workers || Time.current > deadline

first_bucket = []
complete = []
last = {}
# One searcher per query: truffler caps Smart runs per user (user_caps[:rerank]).
EXAMPLES.each_with_index do |query, index|
  user = User.create!(email_address: "bench-smart-#{index}@every.to", name: "Bench #{index}")
  SearchLatency.encode!(query, user)
  OPTIONS[:smart].times do
    FeedSearch.cancel(user: user)
    t0 = SearchLatency.now
    run = FeedSearch.smart(query, user: user)
    first = nil
    loop do
      smart = FeedSearch.find_run(run.id, user: user).to_h
      elapsed = SearchLatency.now - t0
      first ||= elapsed if smart[:buckets].values.any?(&:present?)
      if %i[complete paused expired cancelled].include?(smart[:status]) || elapsed > 30
        complete << elapsed
        last[query] = smart
        break
      end
      sleep 0.01
    end
    first_bucket << first if first
  end
end

puts
puts "Smart search (Enter -> bucket readable; add ~#{100} ms client coalesce + one partial reload)"
puts "  first bucket      #{SearchLatency.summary(first_bucket)}"
puts "  all buckets       #{SearchLatency.summary(complete)}"
EXAMPLES.each do |query|
  smart = last[query]
  sizes = smart[:buckets].transform_values(&:size)
  top = smart[:buckets][:strong].first(3).map { |entry| Item.find(entry[:id]).messages.first.body.truncate(60) }
  puts "  #{query.inspect}: #{smart[:status]}, #{sizes.inspect}; strong: #{top.inspect}"
end
