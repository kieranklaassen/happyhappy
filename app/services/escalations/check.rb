module Escalations
  # Decides whether a freshly classified item escalates to its product's Slack
  # channel (R28, R30) and enqueues the post. Runs from the item.classified
  # subscriber in config/initializers/item_events.rb.
  #
  #   Escalations::Check.call(item, message) # => the new Escalation, or nil
  class Check
    MAX_MESSAGE_AGE = 7.days

    def self.call(...)
      new(...).call
    end

    def initialize(item, message = nil)
      @item = item
      @message = message
    end

    def call
      escalation = @item.with_lock do
        next unless escalate?

        @item.escalations.create!(product: product, slack_channel_id: product.slack_channel_id, message: trigger)
      end
      ActiveRecord.after_all_transactions_commit { PostEscalationJob.perform_later(escalation) } if escalation
      escalation
    end

    private

    def escalate?
      @item.relevant? &&
        product&.slack_channel_id.present? &&
        angry?(@item.anger_probability) &&
        trigger.present? &&
        angry?(trigger.anger_probability) &&
        trigger.occurred_at >= MAX_MESSAGE_AGE.ago &&
        !escalated_since_status_change?
    end

    def product
      @item.product
    end

    def angry?(probability)
      probability.present? && probability >= product.effective_escalation_threshold
    end

    # The message whose classification fired the event, else the angriest open message.
    def trigger
      @trigger ||= @message || @item.open_messages.where.not(anger_probability: nil).reorder(anger_probability: :desc).first
    end

    def escalated_since_status_change?
      @item.escalations.where(created_at: @item.status_changed_at..).exists?
    end
  end
end
