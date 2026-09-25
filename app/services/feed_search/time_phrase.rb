module FeedSearch
  TimePhrase = Data.define(:name, :since, :until)

  # Pulls a time window ("today", "this week", "last 30 days") out of a search
  # query. Query encoding only knows labels, so a time phrase would otherwise
  # be read as filler and dropped; here it becomes a feed time filter with its
  # own chip, and the rest of the query goes on to truffler.
  #
  #   FeedSearch::TimePhrase.extract("angry Cora billing this week")
  #   # => ["angry Cora billing", #<TimePhrase name="This week" since=Monday 00:00 until=nil>]
  class TimePhrase
    CHIP_KEY = "time".freeze

    PHRASES = [
      [ /\b(?:in the )?(?:last|past) (\d{1,3}) days?\b/i, ->(now, match) { [ "Last #{match[1]} days", now - match[1].to_i.days ] } ],
      [ /\b(?:in the )?(?:last|past) (\d{1,3}) hours?\b/i, ->(now, match) { [ "Last #{match[1]} hours", now - match[1].to_i.hours ] } ],
      [ /\btoday\b/i, ->(now, _) { [ "Today", now.beginning_of_day ] } ],
      [ /\byesterday\b/i, ->(now, _) { [ "Yesterday", now.yesterday.beginning_of_day, now.beginning_of_day ] } ],
      [ /\bthis week\b/i, ->(now, _) { [ "This week", now.beginning_of_week ] } ],
      [ /\blast week\b/i, ->(now, _) { [ "Last week", now.prev_week.beginning_of_week, now.beginning_of_week ] } ],
      [ /\b(?:in the )?past week\b/i, ->(now, _) { [ "Last 7 days", now - 7.days ] } ],
      [ /\bthis month\b/i, ->(now, _) { [ "This month", now.beginning_of_month ] } ],
      [ /\blast month\b/i, ->(now, _) { [ "Last month", now.prev_month.beginning_of_month, now.beginning_of_month ] } ],
      [ /\b(?:in the )?past month\b/i, ->(now, _) { [ "Last 30 days", now - 30.days ] } ]
    ].freeze

    # Returns [query without the phrase, TimePhrase or nil]. Only the first
    # phrase counts.
    def self.extract(query, now: Time.current)
      text = query.to_s
      PHRASES.each do |pattern, window|
        match = pattern.match(text)
        next unless match

        name, since, before = window.call(now, match)
        return [ "#{match.pre_match} #{match.post_match}".squish, new(name: name, since: since, until: before) ]
      end
      [ text.squish, nil ]
    end

    def filters
      { since: since.iso8601, until: self.until&.iso8601 }.compact
    end

    def chip
      { key: CHIP_KEY, label: CHIP_KEY, kind: "filter", name: name }
    end
  end
end
