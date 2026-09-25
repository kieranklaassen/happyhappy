# Offline classifier evaluation against judge labels (ce-optimize harness).
#
#   DATABASE_URL=sqlite3:/tmp/hh/eval.sqlite3 EVAL_DIR=/tmp/hh EVAL_RUN=baseline \
#     bin/rails runner script/classifier_eval.rb
#
# Loads the exported production threads into a scratch database, ingests every
# message the way a backfill would, classifies each one in order with the current
# code, and scores the rolled-up item labels against the judge's gold labels.
# EVAL_MODE=prod scores the exported production labels instead, without calling
# TypeSafe (EVAL_EXPORT picks another export of the same items, such as one
# taken after a production rerun). Responses are cached by request payload under EVAL_DIR/cache, so an
# unchanged request is never paid for twice. Prints one JSON line of metrics.
require "digest"

dir = Pathname(ENV.fetch("EVAL_DIR"))
run = ENV.fetch("EVAL_RUN", "run")
mode = ENV.fetch("EVAL_MODE", "classify")
database = ActiveRecord::Base.connection_db_config.database.to_s
abort "refusing to run outside a scratch database (#{database})" unless database.start_with?("/tmp/")

export = JSON.parse(dir.join(ENV.fetch("EVAL_EXPORT", "gold_export.json")).read)
gold = Dir[dir.join("judge/labels_*.json")].flat_map { |path| JSON.parse(File.read(path)) }.index_by { |label| label["item_id"] }
taxonomy = JSON.parse(dir.join("taxonomy.json").read)
team_role_ids = ENV.fetch("EVAL_TEAM_ROLE_IDS", "").split(",")
discord_roles = dir.join("discord_member_roles.json").exist? ? JSON.parse(dir.join("discord_member_roles.json").read) : {}

usage = { requests: 0, cached: 0, input_tokens: 0 }
cache_dir = dir.join("cache").tap(&:mkpath)
RubyLLM::Providers::TypeSafe.prepend(Module.new do
  define_method(:complete) do |messages, model:, schema: nil, provider_options: {}, **options, &block|
    payload = RubyLLM::Protocols::SystemOne::Chat.render_payload(messages, model: model, schema: schema,
      state: provider_options[:state])
    path = cache_dir.join("#{Digest::SHA256.hexdigest(JSON.generate(payload))}.json")
    usage[:requests] += 1
    if path.exist?
      usage[:cached] += 1
      cached = JSON.parse(path.read)
      next RubyLLM::Message.new(role: :assistant, content: cached["content"], model: cached["model"],
        input_tokens: cached["input_tokens"], output_tokens: 0)
    end

    response = super(messages, model: model, schema: schema, provider_options: provider_options, **options, &block)
    usage[:input_tokens] += response.tokens&.input.to_i
    path.write(JSON.generate(content: response.content, model: response.model, input_tokens: response.tokens&.input))
    response
  end
end)

coarse_mood = lambda do |mood|
  case mood
  when "furious", "grumpy" then "upset"
  when "beaming", "content" then "happy"
  when "relieved" then "relieved"
  else "meh"
  end
end
gold_mood = lambda do |label|
  if label["angry"] || label["sentiment"] == "complaint" then "upset"
  elsif label["sentiment"] == "praise" then "happy"
  elsif label["sentiment"] == "relieved" then "relieved"
  else "meh"
  end
end
predicted_mood = lambda do |labels|
  coarse_mood.call(Mood.for(sentiment: labels[:sentiment], anger: labels[:anger],
    sentiment_probability: labels[:sentiment_probability], furious_at: 0.8))
end

predictions =
  if mode == "prod"
    export.to_h do |item|
      prod = item["prod"]
      [ item["id"], { relevant: prod["relevant"], product: prod["product"] || "none", category: prod["category"] || "other",
        sentiment: prod["sentiment"], sentiment_probability: prod["sentiment_probability"], anger: prod["anger_probability"],
        author_roles: item["messages"].to_h { |message| [ message["id"].to_s, message["author_role"] || "customer" ] } } ]
    end
  else
    ActiveRecord::Schema.verbose = false
    ActiveRecord::Migration.suppress_messages { load Rails.root.join("db/schema.rb") }
    ActiveJob::Base.queue_adapter = :test
    setting = Setting.current
    setting.update!(team_discord_role_ids: team_role_ids) if setting.has_attribute?(:team_discord_role_ids)

    products = taxonomy["products"].to_h do |product|
      [ product["slug"], Product.create!(product.slice("slug", "name", "description", "hint_words")) ]
    end
    taxonomy["categories"].each { |category| Category.create!(category.slice("name", "description", "position")) }
    sources = export.map { |item| item.slice("source_id", "source_kind", "source_name", "default_product") }.uniq.to_h do |source|
      [ source["source_id"], Source.create!(kind: source["source_kind"], name: source["source_name"],
        selector: "eval-#{source["source_id"]}", default_product: products[source["default_product"]]) ]
    end

    raw_payload = lambda do |kind, author|
      case kind
      when "discord"
        roles = discord_roles[author["id"].to_s]
        { "guild_id" => "eval", "author" => { "id" => author["id"], "username" => author["username"],
          "global_name" => author["name"] } }.merge(roles ? { "member" => { "roles" => roles } } : {})
      when "intercom"
        { "part" => { "author" => author.slice("type", "name", "email") } }
      else {}
      end
    end

    item_ids = {}
    export.each do |item|
      item["messages"].each do |message|
        author = message["author"]
        inbound = Items::InboundMessage.new(external_id: "m#{message["id"]}", thread_key: "item-#{item["id"]}",
          body: message["body"], occurred_at: message["occurred_at"],
          author_handle: author["username"], author_name: author["name"], author_email: author["email"],
          raw_payload: raw_payload.call(item["source_kind"], author))
        result = Items::Ingest.call(source: sources.fetch(item["source_id"]), inbound: inbound, backfill: true)
        item_ids[item["id"]] = result.item.id
      end
    end

    classifier = Classification.classifier
    export.to_h do |item|
      record = Item.find(item_ids.fetch(item["id"]))
      record.messages.each do |message|
        Classification::Apply.call(message: message, answers: classifier.call(message))
      end
      record.reload
      roles = record.messages.to_h do |message|
        [ message.external_id.delete_prefix("m"), message.has_attribute?(:author_role) ? message.author_role : "customer" ]
      end
      [ item["id"], { relevant: record.relevant, product: record.product&.slug || "none",
        category: record.category&.name || "other", sentiment: record.sentiment,
        sentiment_probability: record.sentiment_probability, anger: record.anger_probability, author_roles: roles } ]
    end
  end

scored = export.select { |item| gold.key?(item["id"]) }
relevant = scored.select { |item| gold[item["id"]]["relevant"] }
fields = {
  "relevance" => [ scored, ->(p, g) { [ p[:relevant] ? "relevant" : "irrelevant", g["relevant"] ? "relevant" : "irrelevant" ] } ],
  "product" => [ relevant, ->(p, g) { [ p[:product], g["product"] ] } ],
  "category" => [ relevant, ->(p, g) { [ p[:category], g["category"] ] } ],
  "sentiment" => [ relevant, ->(p, g) { [ p[:sentiment].to_s, g["sentiment"] ] } ],
  "anger" => [ scored, ->(p, g) { [ p[:anger].to_f >= 0.5 ? "angry" : "calm", g["angry"] ? "angry" : "calm" ] } ],
  "mood" => [ relevant, ->(p, g) { [ predicted_mood.call(p), gold_mood.call(g) ] } ]
}

metrics = {}
details = {}
fields.each do |field, (items, pair)|
  pairs = items.map { |item| pair.call(predictions.fetch(item["id"]), gold[item["id"]]) }
  metrics["#{field}_accuracy"] = (pairs.count { |predicted, expected| predicted == expected }.to_f / pairs.size).round(4)
  details[field] = {
    n: pairs.size,
    confusions: pairs.reject { |predicted, expected| predicted == expected }.tally
      .sort_by { |_, count| -count }.first(12).map { |(predicted, expected), count| "#{expected} -> #{predicted}: #{count}" },
    predicted_minus_gold: (pairs.map(&:first).tally.to_a + pairs.map(&:last).tally.map { |key, count| [ key, -count ] })
      .group_by(&:first).transform_values { |entries| entries.sum(&:last) }.reject { |_, delta| delta.zero? }
  }
end

role_pairs = scored.flat_map do |item|
  gold[item["id"]]["author_roles"].map { |id, role| [ predictions.fetch(item["id"])[:author_roles][id.to_s] || "missing", role ] }
end
metrics["author_role_accuracy"] = (role_pairs.count { |predicted, expected| predicted == expected }.to_f / role_pairs.size).round(4)
details["author_role"] = { n: role_pairs.size, confusions: role_pairs.reject { |a, b| a == b }.tally.map { |(p, g), c| "#{g} -> #{p}: #{c}" } }

multi = relevant.select { |item| item["messages"].size > 1 }
%w[category sentiment mood].each do |field|
  pair = fields[field].last
  hits = multi.count { |item| predicted, expected = pair.call(predictions.fetch(item["id"]), gold[item["id"]]); predicted == expected }
  metrics["#{field}_multi_message_accuracy"] = (hits.to_f / [ multi.size, 1 ].max).round(4)
end
headline = %w[relevance product category sentiment anger mood author_role]
metrics["macro_accuracy"] = (headline.sum { |field| metrics["#{field}_accuracy"] } / headline.size).round(4)
metrics["items_scored"] = scored.size
metrics["typesafe_requests"] = usage[:requests]
metrics["typesafe_cached"] = usage[:cached]
metrics["typesafe_input_tokens"] = usage[:input_tokens]
metrics["typesafe_cost_usd"] = (usage[:input_tokens] * 0.042 / 1_000_000).round(4)

runs = dir.join("runs").tap(&:mkpath)
runs.join("#{run}.json").write(JSON.pretty_generate(metrics: metrics, details: details,
  predictions: predictions.transform_values { |p| p.except(:author_roles) }))
puts JSON.generate(metrics)
