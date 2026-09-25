class CreateAnomalies < ActiveRecord::Migration[8.1]
  def change
    create_table :anomalies do |t|
      t.references :product, null: false, foreign_key: true
      t.references :source, foreign_key: true
      t.string :metric, null: false
      t.string :dimension
      t.string :granularity, null: false
      t.datetime :window_start, null: false
      t.datetime :window_end, null: false
      t.float :expected, null: false
      t.float :actual, null: false
      t.float :z_score, null: false
      t.string :severity, null: false
      t.json :item_ids, null: false, default: []
      t.string :status, null: false, default: "active"
      t.boolean :historical, null: false, default: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :ended_at
      t.timestamps
    end
    add_index :anomalies, [ :product_id, :metric, :dimension, :granularity, :window_start ], name: "index_anomalies_on_series_and_window"
    add_index :anomalies, [ :status, :window_end ]

    change_table :settings, bulk: true do |t|
      t.float :anomaly_sensitivity, null: false, default: 3.0
      t.integer :anomaly_min_count, null: false, default: 5
      t.integer :anomaly_min_baseline_windows, null: false, default: 6
      t.integer :anomaly_active_days, null: false, default: 7
    end
  end
end
