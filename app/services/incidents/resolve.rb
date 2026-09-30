module Incidents
  # Resolves an incident on someone's behalf: a person (web or a Slack user matched by email), an
  # agent (resolve_anomaly), or just a Slack name when nobody matches.
  #
  #   Incidents::Resolve.call(incident:, actor: Current.user, note: "Fixed the IMAP sync", handle_items: true)
  #
  # Ends every anomaly of the incident and stamps it resolved, which also keeps the detector from
  # re-alerting on those series until they calm down (Anomalies::Detect). With handle_items, driving
  # items that still need attention are marked handled with the note as the reason. Then it threads
  # "Resolved by" under the Slack ping and sends the incident.resolved webhook.
  class Resolve
    Result = Data.define(:incident, :error) do
      def success? = error.nil?
      def failure? = !success?
    end

    def self.call(...)
      new(...).call
    end

    def initialize(incident:, actor: nil, actor_name: nil, note: nil, handle_items: false, at: Time.current)
      @incident = incident
      @actor = actor
      @actor_name = actor_name.presence || actor_display_name(actor)
      @note = note.to_s.strip.presence
      @handle_items = ActiveModel::Type::Boolean.new.cast(handle_items) || false
      @at = at
    end

    def call
      return Result.new(incident: @incident, error: "Incident #{@incident.id} is already resolved.") if @incident.resolved?

      @incident.transaction do
        @incident.update!(status: :resolved, resolved_at: @at, resolved_by: @actor, resolved_by_name: @actor_name,
          resolution_note: @note, items_handled: @handle_items)
        @incident.anomalies.each do |anomaly|
          anomaly.update!(status: :ended, ended_at: anomaly.ended_at || @at, resolved_at: @at)
        end
        handle_items! if @handle_items
      end

      PostIncidentResolutionJob.perform_later(@incident) if @incident.slack_posted?
      Rails.error.handle(context: { incident_id: @incident.id }) { Webhooks::FanOut.incident(@incident) }
      Result.new(incident: @incident, error: nil)
    end

    private

    def handle_items!
      reason = [ [ "Incident resolved", @actor_name ].compact.join(" by "), @note ].compact.join(": ")
      Item.where(id: @incident.item_ids).merge(Item.needing_attention).find_each do |item|
        Items::ChangeStatus.call(item: item, status: "handled", actor: @actor, reason: reason)
      end
    end

    def actor_display_name(actor)
      case actor
      when User then actor.name.presence || actor.email_address
      when Agent then actor.name
      end
    end
  end
end
