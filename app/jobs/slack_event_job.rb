class SlackEventJob < ApplicationJob
  queue_as :default
  # The envelope carries the customer's message text.
  self.log_arguments = false

  def perform(envelope)
    Connectors::Slack.new.ingest(envelope)
  end
end
