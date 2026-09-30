module Incidents
  # Puts a new, live, negative anomaly into its product's open incident when that incident's latest
  # anomaly arrived within Setting#incident_window, or opens a new incident, then brings the Slack ping
  # up to date (a first post for a new incident, chat.update for one already posted).
  #
  #   Incidents::Correlate.call(anomaly)   # => Incident, or nil for anomalies that open none
  #   Incidents::Correlate.all(anomalies)  # one scan's new anomalies, one Slack sync per incident
  class Correlate
    def self.call(anomaly, setting: Setting.current)
      new(anomaly, setting:).call.tap { |incident| SyncIncidentSlackJob.perform_later(incident) if incident }
    end

    def self.all(anomalies, setting: Setting.current)
      incidents = anomalies.filter_map do |anomaly|
        Rails.error.handle(context: { anomaly_id: anomaly.id }) { new(anomaly, setting:).call }
      end
      incidents.uniq.each { |incident| SyncIncidentSlackJob.perform_later(incident) }
    end

    def initialize(anomaly, setting: Setting.current)
      @anomaly = anomaly
      @setting = setting
    end

    def call
      return unless @anomaly.incident_worthy? && @anomaly.incident_id.nil?

      at = @anomaly.first_seen_at
      Incident.transaction do
        incident = @anomaly.product.incidents.open.where(last_anomaly_at: (at - @setting.incident_window)..)
          .order(:last_anomaly_at, :id).last
        if incident
          incident.update!(last_anomaly_at: [ incident.last_anomaly_at, at ].max)
        else
          incident = @anomaly.product.incidents.create!(opened_at: at, last_anomaly_at: at)
        end
        @anomaly.update!(incident: incident)
        incident
      end
    end
  end
end
