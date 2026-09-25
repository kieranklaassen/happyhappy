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

    # Backfilled classification yields to live messages on the shared worker.
    BACKFILL_CLASSIFY_PRIORITY = 10

    # classify_wait delays the classification job, for callers that classify
    # inline first and keep the job as the fallback.
    #
    # backfill marks history imported after the fact: it is classified at a lower
    # priority, never reopens a handled item, and its events neither escalate nor
    # fan out to outbound webhooks.
    def initialize(source:, inbound:, classify_wait: nil, backfill: false)
      @source = source
      @inbound = inbound
      @classify_wait = classify_wait
      @backfill = backfill
    end

    def call
      @inbound.validate!

      result = with_unique_retry { store }
      enqueue_classification(result.message) unless result.duplicate?
      result
    end

    private

    def enqueue_classification(message)
      options = {}
      options[:wait] = @classify_wait if @classify_wait
      options[:priority] = BACKFILL_CLASSIFY_PRIORITY if @backfill
      ClassifyMessageJob.set(options).perform_later(message)
    end

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
          raw_payload: @inbound.raw_payload,
          backfilled: @backfill
        )
        item.record_event!(:arrived, message_id: message.id, source_id: @source.id, **backfill_data)
        if !@backfill && REOPENING_STATUSES.include?(item.status)
          item.change_status!(:new, at: message.created_at, reason: "customer_wrote_again", message_id: message.id)
        end
        @source.record_message_received!

        Result.new(item: item, message: message, duplicate: false)
      end
    end

    def backfill_data
      @backfill ? { backfill: true } : {}
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
