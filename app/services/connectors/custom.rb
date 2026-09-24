module Connectors
  # Maps a custom webhook's JSON body to an inbound message and ingests it
  # (KTD3). In sync mode it also classifies inline, bounded by KTD18.
  #
  #   result = Connectors::Custom.call(source: source, raw_body: request.raw_post, sync: true)
  #   result.to_h # => { item_id:, message_id:, duplicate:, classification: "classified", item_status:, labels: }
  #
  # Raises Connectors::Custom::InvalidPayload when the body cannot become a message.
  class Custom
    MAX_BODY_BYTES = 16.kilobytes
    SYNC_TIMEOUT = 10.seconds
    # The queued fallback job starts after the inline attempt has given up.
    SYNC_FALLBACK_DELAY = SYNC_TIMEOUT + 5.seconds

    class InvalidPayload < StandardError; end
    class SyncTimeout < StandardError; end

    Result = Data.define(:item, :message, :duplicate) do
      def to_h
        answers = message.classification_answers if message.classified?
        {
          item_id: item.id,
          message_id: message.id,
          duplicate: duplicate,
          classification: answers ? "classified" : "pending",
          item_status: item.status,
          labels: answers && Custom.labels(answers)
        }
      end
    end

    class << self
      attr_writer :sync_timeout

      def sync_timeout
        @sync_timeout || SYNC_TIMEOUT
      end

      def call(...)
        new(...).call
      end

      def labels(answers)
        {
          relevant: { probability: answers.dig("relevant", "noul") },
          product: choice(answers["product"]),
          category: choice(answers["category"]),
          sentiment: choice(answers["sentiment"]),
          anger: { probability: answers.dig("anger", "noul") }
        }
      end

      private

      def choice(answer)
        return if answer.blank?

        value = answer["choice"]
        probability = answer.dig("probabilities", value) || answer["confidence"]
        { value: value, probability: probability, probabilities: answer["probabilities"] }
      end
    end

    def initialize(source:, raw_body:, sync: false)
      @source = source
      @raw_body = raw_body.to_s
      @sync = sync
    end

    def call
      ingested = Items::Ingest.call(source: @source, inbound: inbound_message(payload),
        classify_wait: (SYNC_FALLBACK_DELAY if @sync))
      if @sync && !ingested.duplicate?
        classify_inline(ingested.message)
        ingested.item.reload
      end

      Result.new(item: ingested.item, message: ingested.message, duplicate: ingested.duplicate?)
    rescue ActiveModel::ValidationError => error
      raise InvalidPayload, error.model.errors.full_messages.to_sentence
    end

    private

    def payload
      parsed = JSON.parse(@raw_body)
      raise InvalidPayload, "body must be a JSON object" unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError
      raise InvalidPayload, "body must be valid JSON"
    end

    def inbound_message(payload)
      text = payload["text"]
      raise InvalidPayload, "text is required" unless text.is_a?(String) && text.present?
      if payload.key?("metadata") && !payload["metadata"].is_a?(Hash)
        raise InvalidPayload, "metadata must be an object"
      end

      external_id = string(payload["id"]) || "sha256:#{Digest::SHA256.hexdigest(@raw_body)}"
      author = author(payload["author"])

      # Items are unique per source kind, so the key carries the source (KTD2);
      # two products may both send thread "1".
      Items::InboundMessage.new(
        external_id: external_id,
        thread_key: "source-#{@source.id}:#{string(payload["thread_key"]) || external_id}",
        body: text,
        occurred_at: occurred_at(payload["occurred_at"]),
        author_name: author["name"],
        author_handle: author["handle"],
        author_email: author["email"],
        permalink: string(payload["permalink"]),
        raw_payload: payload
      )
    end

    def string(value)
      value.to_s.strip.presence if value.is_a?(String) || value.is_a?(Integer)
    end

    def author(value)
      case value
      when String then { "name" => value.strip.presence }
      when Hash then value.slice("name", "handle", "email").transform_values { |field| string(field) }
      when nil then {}
      else raise InvalidPayload, "author must be a string or an object"
      end
    end

    def occurred_at(value)
      return if value.nil?

      Time.zone.iso8601(value.to_s)
    rescue ArgumentError
      raise InvalidPayload, "occurred_at must be an ISO 8601 time"
    end

    # The message is stored and its job is queued, so any classifier failure
    # here only means the answer is pending; the job owns retries and errors.
    def classify_inline(message)
      answers =
        begin
          Timeout.timeout(self.class.sync_timeout, SyncTimeout) { Classification.classifier.call(message) }
        rescue StandardError => error
          Rails.logger.info("[custom webhook] sync classification pending for message #{message.id}: #{error.class}")
          return
        end
      Classification::Apply.call(message: message, answers: answers)
    end
  end
end
