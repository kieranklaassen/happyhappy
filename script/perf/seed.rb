# frozen_string_literal: true

# Production-sized fixture for rendering performance work (development only):
#
#   bin/rails runner script/perf/seed.rb
#
# Replaces every item, message, and timeline event with ~4,000 items and 20,000+ messages across
# nine products and 90 days, every mood, and a few very long threads where the team replies every
# third message. Deterministic, so runs compare.
# Rows are bulk-inserted, so no callbacks, classifications, or broadcasts run.
abort "script/perf/seed.rb only runs in development" unless Rails.env.development?

ITEMS = Integer(ENV.fetch("ITEMS", 4_000))
AUTHORS = 1_500
random = Random.new(42)
now = Time.current

PRODUCTS = %w[Cora Spiral Sparkle Monologue Proof Lex Thesis Babble Studio].freeze
PHRASES = [
  "The morning brief skipped half my inbox again.", "Honestly this is the best tool I pay for.",
  "Can I export my drafts to Google Docs?", "It keeps renaming my screenshots with emoji.",
  "I was charged twice this month, please refund one.", "Support answered in five minutes, wow.",
  "Dictation turned 'quarterly review' into 'quarterly revenge'.", "Any plans for a Windows version?",
  "Why did it archive my landlord's email as a newsletter?", "Love the new screener, it caught everything.",
  "Still waiting on a reply from last week.", "The draft sounds exactly like me, which is a little scary.",
  "Is there a keyboard shortcut for regenerate?", "It crashed when I opened a folder with 10,000 files.",
  "Thank you for fixing the sync bug so fast.", "This update broke my workflow completely.",
  "How do I connect a second account?", "Meh, it's fine I guess.", "WHO APPROVED THIS FEATURE",
  "Quick question about pricing for teams."
].freeze
MOODS = [ # sentiment, sentiment probability, anger, weight
  [ "praise", 0.92, 0.02, 22 ], [ "praise", 0.62, 0.05, 12 ], [ "question", 0.8, 0.08, 16 ],
  [ "neutral", 0.7, 0.12, 12 ], [ "relieved", 0.85, 0.05, 6 ], [ "complaint", 0.8, 0.5, 16 ], [ "complaint", 0.9, 0.93, 8 ],
  [ nil, nil, nil, 5 ]
].freeze
MOOD_BAG = MOODS.flat_map { |mood| [ mood ] * mood.last }

def body(random)
  Array.new(random.rand(1..4)) { PHRASES.sample(random: random) }.join(" ")
end

def thread_length(random)
  roll = random.rand
  if roll < 0.70 then random.rand(1..3)
  elsif roll < 0.95 then random.rand(4..10)
  elsif roll < 0.99 then random.rand(11..40)
  else random.rand(80..250)
  end
end

def last_seen(random, now)
  roll = random.rand
  if roll < 0.015 then now - random.rand(0.0..24.0).hours
  elsif roll < 0.165 then now - random.rand(1.0..7.0).days
  else now - random.rand(7.0..90.0).days
  end
end

ActiveRecord::Base.transaction do
  [ ItemEvent, Escalation, Message ].each(&:delete_all)
  Item.delete_all

  products = PRODUCTS.map { |name| Product.find_or_create_by!(name: name) { |product| product.description = "#{name}, by Every." } }
  categories = Category.order(:position).to_a
  sources = { "slack" => 3, "discord" => 3, "intercom" => 1, "email" => 2, "x" => 1 }.flat_map do |kind, count|
    Array.new(count) do |index|
      Source.find_or_create_by!(kind: kind, selector: "perf-#{kind}-#{index}") { |source| source.name = "Perf #{kind} #{index}" }
    end
  end

  item_rows = Array.new(ITEMS) do |index|
    source = sources.sample(random: random)
    sentiment, confidence, anger, = MOOD_BAG.sample(random: random)
    author = random.rand(AUTHORS)
    seen = last_seen(random, now)
    {
      source_id: source.id, source_kind: source.kind, thread_key: "perf-#{index}",
      author_handle: (source.kind == "email" ? nil : "fan_#{author}"),
      author_email: (source.kind == "email" ? "fan#{author}@example.com" : nil),
      author_name: (author.even? ? "Fan #{author}" : nil),
      permalink: "https://example.com/threads/#{index}",
      status: %w[new new new claimed in_progress handled dismissed].sample(random: random),
      status_changed_at: seen - 1.hour, product_id: products.sample(random: random).id,
      category_id: categories.sample(random: random).id, sentiment: sentiment,
      sentiment_probability: confidence, product_probability: random.rand(0.4..0.99),
      category_probability: random.rand(0.4..0.99), relevance_probability: random.rand(0.5..1.0),
      anger_probability: anger, relevant: random.rand > 0.1, needs_review: random.rand < 0.08,
      last_message_at: seen, created_at: seen - 2.days, updated_at: seen
    }
  end
  item_rows.each_slice(1_000) { |slice| Item.insert_all!(slice) }

  message_rows = []
  event_rows = []
  Item.pluck(:id, :source_id, :last_message_at, :anger_probability).each do |id, source_id, seen, anger|
    count = thread_length(random)
    count.times do |position|
      at = seen - ((count - position - 1) * random.rand(5..90)).minutes
      message_rows << { item_id: id, source_id: source_id, external_id: "perf-#{id}-#{position}", body: body(random),
        author_role: (position % 3 == 2 ? "team" : "customer"),
        occurred_at: at, anger_probability: anger, classified_at: anger && at, backfilled: at < now - 7.days,
        raw_payload: {}, created_at: at, updated_at: at }
      event_rows << { item_id: id, kind: "arrived", data: {}, created_at: at }
      event_rows << { item_id: id, kind: "classified", data: { anger: anger }, created_at: at + 2.seconds } if anger
    end
  end
  message_rows.each_slice(2_000) { |slice| Message.insert_all!(slice) }
  event_rows.each_slice(2_000) { |slice| ItemEvent.insert_all!(slice) }
end

puts "perf fixture: #{Product.count} products, #{Item.count} items, #{Message.count} messages, " \
  "#{ItemEvent.count} events, longest thread #{Message.group(:item_id).count.values.max} messages"
