# frozen_string_literal: true

class ListAnomaliesTool < ApplicationTool
  DEFAULT_LIMIT = 25
  MAX_LIMIT = 100
  STATUSES = (DetectedAnomaly.statuses.values + %w[all]).freeze

  tool_name "list_anomalies"
  description <<~TEXT.squish
    List anomalies happyhappy detected in product series (message volume, complaint share, mean anger,
    share of customers in each mood, and per-category volume), most recent window first. Each carries
    the expected and actual value, severity, status, and the ids of the items that drove it; pass those
    to get_item. Defaults to active anomalies.
  TEXT
  input_schema(
    properties: {
      product: { type: "string", description: "Product id or slug." },
      status: { type: "string", enum: STATUSES, description: "Defaults to active." },
      granularity: { type: "string", enum: DetectedAnomaly::GRANULARITIES.keys },
      limit: { type: "integer", minimum: 1, maximum: MAX_LIMIT, description: "Defaults to #{DEFAULT_LIMIT}." }
    }
  )
  annotations(read_only_hint: true, open_world_hint: false)

  def call
    status = arguments.fetch(:status, "active")
    raise Error, "Invalid filter status: must be one of #{STATUSES.join(', ')}" unless STATUSES.include?(status)

    scope = DetectedAnomaly.includes(:product, :source).recent_first
    scope = scope.where(status: status) unless status == "all"
    scope = scope.where(granularity: arguments[:granularity]) if arguments[:granularity].present?
    scope = scope.where(product: product) if arguments[:product].present?

    { anomalies: scope.limit(arguments.fetch(:limit, DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)).map(&:to_props) }
  end

  private

  def product
    slug_or_id = arguments[:product]
    Product.find_by(slug: slug_or_id) || Product.find_by(id: slug_or_id) or raise Error, "Product #{slug_or_id} was not found."
  end
end
