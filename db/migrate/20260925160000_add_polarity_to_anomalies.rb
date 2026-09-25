class AddPolarityToAnomalies < ActiveRecord::Migration[8.1]
  class MigrationAnomaly < ActiveRecord::Base
    self.table_name = "anomalies"
  end

  SEVERITIES = %w[low medium high].freeze
  HIGHLIGHTS = %w[notable big huge].freeze

  def up
    add_column :anomalies, :polarity, :string
    add_column :anomalies, :highlight, :string
    change_column_null :anomalies, :severity, true

    MigrationAnomaly.reset_column_information
    MigrationAnomaly.find_each do |anomaly|
      polarity = Anomalies::Polarity.for(metric: anomaly.metric, dimension: anomaly.dimension, item_ids: anomaly.item_ids)
      level = SEVERITIES.index(anomaly.severity) || 0
      anomaly.update_columns(
        polarity: polarity,
        severity: (SEVERITIES[level] if polarity == "negative"),
        highlight: (HIGHLIGHTS[level] if polarity == "positive")
      )
    end

    change_column_default :anomalies, :polarity, from: nil, to: "neutral"
    change_column_null :anomalies, :polarity, false
  end

  def down
    MigrationAnomaly.reset_column_information
    MigrationAnomaly.where(severity: nil).find_each do |anomaly|
      anomaly.update_columns(severity: SEVERITIES[HIGHLIGHTS.index(anomaly.highlight) || 0])
    end
    change_column_null :anomalies, :severity, false
    remove_column :anomalies, :highlight
    remove_column :anomalies, :polarity
  end
end
