class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.float :low_confidence_threshold, null: false, default: 0.6
      t.float :escalation_threshold, null: false, default: 0.8
      t.integer :report_back_window_minutes, null: false, default: 240
      t.timestamps
    end
  end
end
