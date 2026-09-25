# frozen_string_literal: true

# Changes 50 of this week's items one commit at a time, the way a classification backlog clearing or
# a backfill looks to open dashboards (development only). Used by script/perf/browser.mjs.
abort "script/perf/burst.rb only runs in development" unless Rails.env.development?

items = Item.relevant.where(last_message_at: 7.days.ago..).order(:id).limit(50).to_a
puts "burst #{items.size}"
$stdout.flush
items.each_with_index do |item, index|
  if item.sentiment == "praise"
    item.update!(sentiment: "complaint", sentiment_probability: 0.9, anger_probability: 0.95)
  else
    item.update!(sentiment: "praise", sentiment_probability: 0.9, anger_probability: 0.01 + index / 1000.0)
  end
end
