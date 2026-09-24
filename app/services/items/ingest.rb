module Items
  # Stores one inbound message on its thread's item and enqueues classification.
  #
  #   result = Items::Ingest.call(source: source, inbound: Items::InboundMessage.new(...))
  #   result.item, result.message, result.duplicate?
  #
  # Raises ActiveModel::ValidationError for an invalid inbound message and stores nothing.
  class Ingest
    REOPENING_STATUSES = %w[handled dismissed].freeze

    Result = Data.define(:item, :message, :duplicate) do
      alias_method :duplicate?, :duplicate
    end

    def self.call(...)
      new(...).call
    end

    def initialize(source:, inbound:)
      @source = source
      @inbound = inbound
    end

    def call
      @inbound.validate!

      result = with_unique_retry { store }
      ClassifyMessageJob.perform_later(result.message) unless result.duplicate?
      result
    end

    private

    def store
      ApplicationRecord.transaction do
        if (existing = @source.messages.find_by(external_id: @inbound.external_id))
          @source.record_message_received!
          next Result.new(item: existing.item, message: existing, duplicate: true)
        end

        item = upsert_item
        message = item.messages.create!(
          source: @source,
          external_id: @inbound.external_id,
          body: @inbound.body,
          occurred_at: @inbound.occurred_at,
          raw_payload: @inbound.raw_payload
        )
        item.record_event!(:arrived, message_id: message.id, source_id: @source.id)
        if REOPENING_STATUSES.include?(item.status)
          item.change_status!(:new, at: message.created_at, reason: "customer_wrote_again", message_id: message.id)
        end
        @source.record_message_received!

        Result.new(item: item, message: message, duplicate: false)
      end
    end

    def upsert_item
      item = Item.find_or_initialize_by(source_kind: @source.kind, thread_key: @inbound.thread_key)
      if item.new_record?
        item.source = @source
        item.product = @source.default_product
      end
      item.author_handle ||= @inbound.author_handle
      item.author_name ||= @inbound.author_name
      item.author_email ||= @inbound.author_email
      item.permalink ||= @inbound.permalink
      item.last_message_at = [ item.last_message_at, @inbound.occurred_at ].compact.max
      item.save!
      item
    end

    # Two deliveries of the same message or thread can race past the lookups;
    # the unique indexes decide, and the retry takes the duplicate path.
    def with_unique_retry
      attempts = 0
      begin
        yield
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts < 2
        raise
      end
    end
  end
end
