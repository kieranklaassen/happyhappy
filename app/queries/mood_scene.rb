# frozen_string_literal: true

# The mood dashboard's data: one character per customer per product for the
# window, drawn from their latest thread, plus the summary for the same window.
class MoodScene
  RANGES = { "24h" => 24.hours, "7d" => 7.days }.freeze
  DEFAULT_RANGE = "24h"
  CHARACTERS_PER_PRODUCT = 48
  ITEM_LIMIT = 2_000
  EXCERPT_LENGTH = 220

  attr_reader :range, :product

  def initialize(range: nil, product: nil, now: Time.current)
    @range = RANGES.key?(range) ? range : DEFAULT_RANGE
    @product = product
    @now = now
  end

  def props
    {
      scene: groups.map { |group| group_props(group) },
      today: summary_props,
      filters: { range: range, product: product&.slug },
      options: {
        ranges: RANGES.keys,
        products: Product.active.ordered.map { |option| { slug: option.slug, name: option.name } }
      }
    }
  end

  private

  Person = Data.define(:item, :seed, :threads, :mood)
  Group = Data.define(:product, :people, :overflow)

  def items
    @items ||= begin
      scope = Item.relevant.includes(:product)
        .where(last_message_at: (@now - RANGES.fetch(range))..)
        .recent_first
        .limit(ITEM_LIMIT)
      product ? scope.where(product: product) : scope
    end
  end

  def people
    @people ||= items.group_by { |item| [ item.product_id, author_key(item) ] }.map do |(_, key), threads|
      latest = threads.first
      Person.new(item: latest, seed: Digest::SHA256.hexdigest(key).first(16), threads: threads.size,
        mood: mood_for(latest))
    end
  end

  def groups
    people.group_by { |person| person.item.product }
      .sort_by { |group_product, _| group_product ? [ 0, group_product.name ] : [ 1, "" ] }
      .map do |group_product, members|
        Group.new(product: group_product, people: members.first(CHARACTERS_PER_PRODUCT),
          overflow: [ members.size - CHARACTERS_PER_PRODUCT, 0 ].max)
      end
  end

  def group_props(group)
    moods = group.people.map(&:mood)
    {
      product: group.product && { slug: group.product.slug, name: group.product.name, retired: group.product.retired? },
      mood: Mood.overall(moods),
      counts: counts(moods),
      overflow: group.overflow,
      characters: group.people.map { |person| character_props(person) }
    }
  end

  def summary_props
    moods = people.map(&:mood)
    tally = counts(moods)
    {
      range: range,
      mood: Mood.overall(moods),
      people: moods.size,
      counts: tally,
      smiling: tally["beaming"] + tally["content"],
      grumpy: tally["grumpy"] + tally["furious"],
      updated_at: @now.iso8601
    }
  end

  def counts(moods)
    (Mood::ALL + [ Mood::PENDING ]).index_with { |mood| moods.count(mood) }
  end

  def character_props(person)
    item = person.item
    {
      key: "#{item.product_id || 'none'}-#{person.seed}",
      seed: person.seed,
      item_id: item.id,
      name: display_name(item),
      handle: handle(item),
      mood: person.mood,
      sentiment: item.sentiment,
      anger: item.anger_probability&.round(2),
      source_kind: item.source_kind,
      status: item.status,
      threads: person.threads,
      excerpt: latest_bodies[item.id].to_s.squish.truncate(EXCERPT_LENGTH),
      last_message_at: item.last_message_at.iso8601,
      mended: item.status_handled? && %w[grumpy furious].include?(person.mood)
    }
  end

  def mood_for(item)
    Mood.for(sentiment: item.sentiment, anger: item.anger_probability,
      sentiment_probability: item.sentiment_probability, furious_at: furious_at(item.product))
  end

  def furious_at(item_product)
    item_product&.escalation_threshold || default_escalation_threshold
  end

  def default_escalation_threshold
    @default_escalation_threshold ||= Setting.current.escalation_threshold
  end

  def latest_bodies
    @latest_bodies ||= begin
      ids = people.map { |person| person.item.id }
      latest_ids = Message.where(item_id: ids).group(:item_id).select("MAX(messages.id)")
      Message.where(id: latest_ids).pluck(:item_id, :body).to_h
    end
  end

  # Same person across threads: email first, then a handle scoped to its source kind.
  def author_key(item)
    if item.author_email.present? then "email:#{item.author_email.strip.downcase}"
    elsif item.author_handle.present? then "#{item.source_kind}:#{item.author_handle.strip.downcase}"
    elsif item.author_name.present? then "#{item.source_kind}:name:#{item.author_name.strip.downcase}"
    else "item:#{item.id}"
    end
  end

  def display_name(item)
    item.author_name.presence || item.author_handle.presence&.then { |value| "@#{value}" } ||
      item.author_email.to_s.split("@").first.presence || "Someone"
  end

  def handle(item)
    item.author_handle.present? ? "@#{item.author_handle}" : item.author_email
  end
end
