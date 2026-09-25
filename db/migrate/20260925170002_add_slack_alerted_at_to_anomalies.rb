class AddSlackAlertedAtToAnomalies < ActiveRecord::Migration[8.1]
  def change
    add_column :anomalies, :slack_alerted_at, :datetime
  end
end
