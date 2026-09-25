# frozen_string_literal: true

# Development-only customers for the mood dashboard. `mood:demo` fills today's
# crowd with every mood; `mood:drift` keeps new messages arriving and moods
# changing so the live dashboard has something to react to.
module MoodDemo
  module_function

  PRODUCTS = {
    "cora" => [ "Cora", "AI email assistant that screens and summarizes your inbox.", "Cora assistant" ],
    "spiral" => [ "Spiral", "Writing tool that turns rough notes into drafts in your voice.", "Spiral ghostwriter" ],
    "sparkle" => [ "Sparkle", "Mac app that organizes your files automatically.", "Sparkle organizer" ],
    "monologue" => [ "Monologue", "Voice dictation that writes like you talk.", "Monologue dictation" ]
  }.freeze

  # product, source kind, author, sentiment, sentiment probability, anger, body
  PEOPLE = [
    [ "cora", "slack", "ana_customer", "complaint", 0.9, 0.91, "Cora archived my landlord's email as a newsletter. I nearly lost my apartment. Fix this TODAY." ],
    [ "cora", "intercom", "bo@example.com", "complaint", 0.8, 0.52, "Charged twice this month. I like Cora, I do not like paying for it twice." ],
    [ "cora", "x", "inboxzeroqueen", "praise", 0.95, 0.02, "Cora's morning brief is the only newsletter I actually read. I am at inbox zero for the first time since 2014." ],
    [ "cora", "email", "cy@example.com", "question", 0.85, 0.08, "How do I connect a second Gmail account?" ],
    [ "cora", "slack", "priya_writes", "praise", 0.6, 0.05, "The new screener is pretty good, it caught most of the spam." ],
    [ "cora", "discord", "grumbles", "complaint", 0.7, 0.35, "Brief arrived at 11am instead of 7am. Again." ],
    [ "cora", "x", "hotmailhenry", "neutral", 0.7, 0.12, "Trying Cora this week, will report back." ],
    [ "cora", "intercom", "dana@example.com", "praise", 0.9, 0.01, "Your support person Kate is a legend. Thank you!" ],
    [ "cora", "slack", "mx_rage", "complaint", 0.95, 0.97, "Cora replied to my BOSS with a haiku. Who approved this feature?" ],
    [ "spiral", "discord", "writerbee", "praise", 0.93, 0.02, "Spiral turned my messy notes into a newsletter draft in five minutes. Love it." ],
    [ "spiral", "discord", "novelnate", "praise", 0.88, 0.03, "Wrote my whole wedding speech with Spiral. Nobody cried, which is a win for my family." ],
    [ "spiral", "x", "ghostwritergreta", "praise", 0.65, 0.04, "Spiral nailed my voice, a little too well honestly." ],
    [ "spiral", "slack", "ed_edits", "question", 0.8, 0.1, "Can Spiral do footnotes?" ],
    [ "spiral", "email", "fran@example.com", "complaint", 0.75, 0.48, "The draft kept calling my cat 'the protagonist'." ],
    [ "spiral", "discord", "loremipsum", "neutral", 0.7, 0.06, "Is there a keyboard shortcut for regenerate?" ],
    [ "spiral", "x", "copycathy", "praise", 0.97, 0.0, "SPIRAL. IS. MAGIC." ],
    [ "sparkle", "x", "dee_posts", "neutral", 0.7, 0.1, "Trying out that new file organizer from Every. Not sure yet." ],
    [ "sparkle", "email", "gus@example.com", "complaint", 0.85, 0.83, "Sparkle moved my tax return into a folder called 'Vibes'. Where is it?!" ],
    [ "sparkle", "discord", "folderfiona", "praise", 0.8, 0.02, "My desktop has never been this clean. My mother would be proud." ],
    [ "sparkle", "slack", "hank_h", "complaint", 0.7, 0.3, "Sparkle keeps renaming screenshots with emoji." ],
    [ "sparkle", "intercom", "ivy@example.com", "question", 0.8, 0.15, "Does Sparkle work with iCloud Drive?" ],
    [ "monologue", "x", "talkytom", "praise", 0.92, 0.01, "Dictated this whole post with Monologue while walking my dog." ],
    [ "monologue", "discord", "mumblemae", "complaint", 0.8, 0.62, "It transcribed 'quarterly review' as 'quarterly revenge'. My manager saw." ],
    [ "monologue", "email", "jo@example.com", "neutral", 0.7, 0.05, "Using it daily. It's fine." ],
    [ "monologue", "slack", "kai_speaks", "praise", 0.7, 0.03, "Pretty handy for meeting notes." ],
    [ "spiral", "slack", "just_arrived", nil, nil, nil, "hey so I have a quick question about spiral and also a long story" ]
  ].freeze

  def source(kind)
    Source.find_or_create_by!(kind: kind, selector: "demo-#{kind}") { |source| source.name = "Demo #{kind}" }
  end

  def product(slug)
    name, description, search_blurb = PRODUCTS.fetch(slug)
    Product.find_by(slug: slug) || Product.create!(slug: slug, name: name, description: description, search_blurb: search_blurb)
  end

  def author(author)
    author.include?("@") ? { author_email: author, author_name: author.split("@").first.capitalize } : { author_handle: author }
  end

  BUG_REPORTERS = %w[ana_customer mx_rage grumbles].freeze
  QUIET_CORA = %w[bo@example.com cy@example.com priya_writes hotmailhenry dana@example.com].freeze
  FANS = %w[writerbee novelnate copycathy].freeze
  QUIET_SPIRAL = %w[ed_edits fran@example.com loremipsum].freeze

  # A steady trickle of messages over the past half day, then a burst in the last hour, so hourly
  # anomaly detection has something to find: bug reports on Cora (bad news) and praise on Spiral
  # (good news).
  def seed_anomaly!
    seed_burst!(category: "bug", description: "Something is broken.", quiet: QUIET_CORA, loud: BUG_REPORTERS,
      tag: "anomaly", body: "Cora archived important mail again. This is broken.", anger: 0.75)
    seed_burst!(category: "praise", description: "Thanks, compliments, and happy stories.", quiet: QUIET_SPIRAL,
      loud: FANS, tag: "praise", body: "Spiral just saved my deadline again. Thank you!", anger: 0.02)
    Anomalies::Detect.call(granularity: "hour")
  end

  def seed_burst!(category:, description:, quiet:, loud:, tag:, body:, anger:)
    category = Category.find_or_create_by!(name: category) { |record| record.description = description }
    loud = loud.map { |author| Item.find_by!(thread_key: "demo-#{author}") }
    loud.each { |item| item.update!(category: category) }
    quiet = quiet.map { |author| Item.find_by!(thread_key: "demo-#{author}") }
    last_window_start, last_window_end = Anomalies::Detect.windows("hour").last

    (2..13).each do |hours|
      (hours.even? ? 1 : 2).times do |index|
        demo_message!(quiet[(hours + index) % quiet.size], "demo-#{tag}-baseline-#{hours}-#{index}",
          last_window_end - hours.hours + (index * 20 + 5).minutes, "Quick question about my settings.")
      end
    end
    8.times do |index|
      demo_message!(loud[index % loud.size], "demo-#{tag}-burst-#{index}",
        last_window_start + (index * 6 + 3).minutes, body, anger: anger)
    end
  end

  def demo_message!(item, external_id, at, body, anger: 0.1)
    message = item.messages.find_or_initialize_by(source: item.source, external_id: external_id)
    message.update!(body: body, occurred_at: at, anger_probability: anger, classified_at: at)
  end

  def classify!(item, sentiment:, confidence:, anger:, body:, at: Time.current)
    message = item.messages.create!(source: item.source, external_id: SecureRandom.uuid, body: body,
      occurred_at: at, anger_probability: anger, classified_at: sentiment && Time.current)
    item.update!(sentiment: sentiment, sentiment_probability: confidence, anger_probability: anger,
      relevant: true, last_message_at: message.occurred_at)
  end
end

namespace :mood do
  desc "Fill the mood dashboard with demo customers (development only)"
  task demo: :environment do
    abort "mood:demo only runs in development" unless Rails.env.development?

    MoodDemo::PEOPLE.each_with_index do |(slug, kind, author, sentiment, confidence, anger, body), index|
      source = MoodDemo.source(kind)
      item = Item.find_or_initialize_by(source_kind: kind, thread_key: "demo-#{author}")
      at = (index * 7).minutes.ago
      item.update!(source: source, product: MoodDemo.product(slug), last_message_at: at, **MoodDemo.author(author))
      MoodDemo.classify!(item, sentiment: sentiment, confidence: confidence, anger: anger, body: body, at: at)
    end
    puts "#{MoodDemo::PEOPLE.size} demo customers are on the dashboard."
    anomalies = MoodDemo.seed_anomaly!
    puts "#{anomalies.size} anomalies detected from a burst of Cora bug reports and Spiral praise."
  end

  desc "Keep demo customers arriving and changing mood (development only)"
  task drift: :environment do
    abort "mood:drift only runs in development" unless Rails.env.development?

    interval = ENV.fetch("INTERVAL", "4").to_f
    newcomers = %w[pat_the_new sam_sunshine lee_lurker]
    moods = [
      [ "praise", 0.95, 0.01, "Okay this update is incredible, thank you!" ],
      [ "complaint", 0.9, 0.93, "It happened AGAIN. I want a human right now." ],
      [ "complaint", 0.7, 0.5, "Still a bit broken for me." ],
      [ "neutral", 0.7, 0.1, "Hm, fine I guess." ],
      [ "praise", 0.65, 0.04, "That fixed it, thanks." ]
    ]
    loop do
      if newcomers.any? && rand < 0.35
        author = newcomers.shift
        item = Item.create!(source: MoodDemo.source("slack"), product: MoodDemo.product(MoodDemo::PRODUCTS.keys.sample),
          thread_key: "demo-#{author}", author_handle: author, last_message_at: Time.current)
        puts "#{author} arrived, still being read"
        sleep interval
        sentiment, confidence, anger, body = moods.sample
        MoodDemo.classify!(item, sentiment: sentiment, confidence: confidence, anger: anger, body: body)
        puts "#{author} is now #{sentiment}"
      else
        item = Item.where("thread_key LIKE 'demo-%'").order("RANDOM()").first
        sentiment, confidence, anger, body = moods.sample
        MoodDemo.classify!(item, sentiment: sentiment, confidence: confidence, anger: anger, body: body)
        puts "#{item.author_handle || item.author_email} says: #{body}"
      end
      sleep interval
    end
  end
end
