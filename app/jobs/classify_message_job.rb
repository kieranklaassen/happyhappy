class ClassifyMessageJob < ApplicationJob
  ATTEMPTS = 5
  PROVIDER_ERRORS = [
    RubyLLM::Error, RubyLLM::ConfigurationError, Faraday::Error, Classification::RateLimiter::Exhausted
  ].freeze

  # Items::Ingest moves backfilled messages to its backfill queue.
  queue_as :realtime

  retry_on(*PROVIDER_ERRORS, attempts: ATTEMPTS, wait: :polynomially_longer) do |job, error|
    job.record_failure(error)
  end

  def perform(message)
    return if message.classified?

    Current.set(backfill: message.backfilled?) do
      Classification::Apply.call(message: message, answers: Classification.classifier.call(message))
    end
  end

  # The item keeps its current labels and status, so it stays in the feed.
  def record_failure(error)
    message = arguments.first
    detail = "#{error.class}: #{error.message}"
    Message.transaction do
      message.update!(classification_error: detail)
      message.item.record_event!(:classification_failed, message_id: message.id, error: detail, attempts: executions)
    end
  end
end
