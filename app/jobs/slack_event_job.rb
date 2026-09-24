class SlackEventJob < ApplicationJob
  queue_as :default

  def perform(envelope)
    Connectors::Slack.new.ingest(envelope)
  end
end
