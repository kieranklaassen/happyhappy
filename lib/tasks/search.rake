# frozen_string_literal: true

# Feed search (U25, docs/search.md). `search:reindex` rebuilds the full-text
# index and rewrites every supplied label (free: no Jev call). `search:demo`
# adds development items spread over a few weeks so time phrases, categories,
# and actionability have something to find.
module SearchDemo
  module_function

  CATEGORIES = {
    "billing" => "Charges, refunds, invoices, and plans.",
    "bug" => "Something is broken.",
    "praise" => "Thanks, compliments, and happy stories.",
    "question" => "Asking how something works."
  }.freeze

  THESIS = [ "Thesis", "Demo product for feed search: research notes that argue back." ].freeze

  # product, category, source kind, author, sentiment, anger, actionability, days ago, body
  ITEMS = [
    [ "cora", "billing", "intercom", "rae@example.com", "complaint", 0.88, 0.93, 1,
      "Cora billed me three times this week and nobody answers. I want my money back or I am cancelling." ],
    [ "cora", "billing", "email", "sol@example.com", "complaint", 0.74, 0.8, 2,
      "The annual plan renewed without warning. Refund it, I switched to monthly months ago." ],
    [ "cora", "billing", "slack", "invoice_ivan", "question", 0.1, 0.55, 3, "Where do I download invoices for my team?" ],
    [ "cora", "billing", "intercom", "old@example.com", "complaint", 0.82, 0.7, 12,
      "Double charge again this month. Please refund." ],
    [ "thesis", "praise", "discord", "phd_pat", "praise", 0.01, 0.1, 0,
      "Thesis found the hole in my argument before my advisor did. Incredible." ],
    [ "thesis", "praise", "x", "citecarla", "praise", 0.02, 0.05, 4, "Thesis citations are spot on. Recommending it to my whole lab." ],
    [ "thesis", "bug", "email", "quinn@example.com", "complaint", 0.55, 0.92, 0,
      "Thesis lost the last hour of my notes when I exported. I need them for a defense tomorrow." ],
    [ "sparkle", "bug", "intercom", "urgent@example.com", "complaint", 0.93, 0.97, 0,
      "Sparkle deleted my client folder. I need someone on this right now." ],
    [ "monologue", "question", "slack", "wren_asks", "question", 0.05, 0.65, 6, "Can Monologue dictate in Dutch?" ]
  ].freeze

  def category(name)
    Category.find_or_create_by!(name: name) { |category| category.description = CATEGORIES.fetch(name) }
  end

  def product(slug)
    return MoodDemo.product(slug) unless slug == "thesis"

    Product.find_by(slug: slug) || Product.create!(slug: slug, name: THESIS.first, description: THESIS.last)
  end

  # mood:demo items carry sentiment and anger only; give them the rest of what
  # classification would have written.
  def complete_mood_demo!
    Item.where("thread_key LIKE 'demo-%'").where.not(sentiment: nil).find_each do |item|
      name = { "praise" => "praise", "question" => "question" }.fetch(item.sentiment, item.category&.name || "bug")
      actionability = item.sentiment == "praise" ? 0.1 : [ item.anger_probability.to_f + 0.1, 0.99 ].min
      classify!(item, category: category(name), actionability: actionability)
    end
  end

  def classify!(item, category:, actionability:)
    item.update!(category: category, relevance_probability: 0.95, relevant: true, actionability: actionability,
      actionability_band: Actionability.band(score: actionability, relevant: true))
  end

  def seed!
    ITEMS.each do |slug, category, kind, author, sentiment, anger, actionability, days, body|
      at = days.days.ago - 30.minutes
      item = Item.find_or_initialize_by(source_kind: kind, thread_key: "search-demo-#{author}")
      item.update!(source: MoodDemo.source(kind), product: product(slug), last_message_at: at, **MoodDemo.author(author))
      MoodDemo.classify!(item, sentiment: sentiment, confidence: 0.9, anger: anger, body: body, at: at)
      classify!(item, category: category(category), actionability: actionability)
    end
  end

  def reindex!
    FeedSearch::TextIndex.rebuild
    Item.find_each(&:truffler_refresh_labels!)
  end
end

namespace :search do
  desc "Rebuild the feed search text index and supplied labels (free: no Jev call)"
  task reindex: :environment do
    SearchDemo.reindex!
    puts "Indexed #{Item.count} items."
  end

  desc "Add demo items for feed search on top of mood:demo (development only)"
  task demo: :environment do
    abort "search:demo only runs in development" unless Rails.env.development?

    Rake::Task["mood:demo"].invoke
    SearchDemo.complete_mood_demo!
    SearchDemo.seed!
    SearchDemo.reindex!
    puts "#{SearchDemo::ITEMS.size} search demo items added; #{Item.count} items indexed. " \
      'Try "angry Cora billing this week", "needs action now", "praise for Thesis".'
  end
end
