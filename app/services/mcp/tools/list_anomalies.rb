module Mcp
  module Tools
    class ListAnomalies < Base
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

      class << self
        def untrusted_content?
          false
        end

        def call(server_context:, product: nil, status: "active", granularity: nil, limit: DEFAULT_LIMIT)
          return failure("Invalid filter status: must be one of #{STATUSES.join(', ')}") unless STATUSES.include?(status)

          scope = DetectedAnomaly.includes(:product, :source).recent_first
          scope = scope.where(status: status) unless status == "all"
          scope = scope.where(granularity: granularity) if granularity.present?
          if product.present?
            record = Product.find_by(slug: product) || Product.find_by(id: product)
            return failure("Product #{product} was not found.") unless record

            scope = scope.where(product: record)
          end

          success(anomalies: scope.limit(limit.to_i.clamp(1, MAX_LIMIT)).map(&:to_props))
        end
      end
    end
  end
end
