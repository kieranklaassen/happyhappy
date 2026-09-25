# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_25_041000) do
  create_table "agents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_agents_on_name", unique: true
    t.index ["token_digest"], name: "index_agents_on_token_digest", unique: true
  end

  create_table "anomalies", force: :cascade do |t|
    t.float "actual", null: false
    t.datetime "created_at", null: false
    t.string "dimension"
    t.datetime "ended_at"
    t.float "expected", null: false
    t.datetime "first_seen_at", null: false
    t.string "granularity", null: false
    t.boolean "historical", default: false, null: false
    t.json "item_ids", default: [], null: false
    t.datetime "last_seen_at", null: false
    t.string "metric", null: false
    t.integer "product_id", null: false
    t.string "severity", null: false
    t.integer "source_id"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.datetime "window_end", null: false
    t.datetime "window_start", null: false
    t.float "z_score", null: false
    t.index ["product_id", "metric", "dimension", "granularity", "window_start"], name: "index_anomalies_on_series_and_window"
    t.index ["product_id"], name: "index_anomalies_on_product_id"
    t.index ["source_id"], name: "index_anomalies_on_source_id"
    t.index ["status", "window_end"], name: "index_anomalies_on_status_and_window_end"
  end

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "retired_at"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_categories_on_name", unique: true
  end

  create_table "digests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.text "last_error"
    t.datetime "posted_at"
    t.integer "product_id", null: false
    t.string "slack_message_ts"
    t.datetime "updated_at", null: false
    t.index ["product_id", "date"], name: "index_digests_on_product_id_and_date", unique: true
  end

  create_table "escalations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "item_id", null: false
    t.text "last_error"
    t.integer "message_id"
    t.datetime "posted_at"
    t.integer "product_id", null: false
    t.string "slack_channel_id", null: false
    t.string "slack_message_ts"
    t.datetime "updated_at", null: false
    t.index ["item_id"], name: "index_escalations_on_item_id"
    t.index ["message_id"], name: "index_escalations_on_message_id"
    t.index ["product_id"], name: "index_escalations_on_product_id"
  end

  create_table "geneva_drive_step_executions", force: :cascade do |t|
    t.datetime "canceled_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_backtrace"
    t.string "error_class_name"
    t.text "error_message"
    t.datetime "failed_at"
    t.datetime "finished_at"
    t.string "job_id"
    t.text "metadata"
    t.string "outcome"
    t.datetime "scheduled_for", null: false
    t.datetime "skipped_at"
    t.datetime "started_at"
    t.string "state", default: "scheduled", null: false
    t.string "step_name", null: false
    t.datetime "updated_at", null: false
    t.integer "workflow_id", null: false
    t.index ["finished_at"], name: "index_geneva_drive_step_executions_on_finished_at"
    t.index ["scheduled_for"], name: "index_geneva_drive_step_executions_on_scheduled_for"
    t.index ["state", "scheduled_for"], name: "index_geneva_drive_step_executions_scheduled"
    t.index ["state"], name: "index_geneva_drive_step_executions_on_state"
    t.index ["workflow_id", "created_at"], name: "idx_on_workflow_id_created_at_af16a14fb2"
    t.index ["workflow_id", "state"], name: "index_geneva_drive_step_executions_on_workflow_id_and_state"
    t.index ["workflow_id"], name: "index_geneva_drive_step_executions_on_workflow_id"
    t.index ["workflow_id"], name: "index_geneva_drive_step_executions_one_active", unique: true, where: "state IN ('scheduled', 'in_progress')"
  end

  create_table "geneva_drive_workflows", force: :cascade do |t|
    t.boolean "allow_multiple", default: false, null: false
    t.datetime "created_at", null: false
    t.string "current_step_name"
    t.integer "hero_id"
    t.string "hero_type"
    t.string "next_step_name"
    t.datetime "started_at"
    t.string "state", default: "ready", null: false
    t.datetime "transitioned_at"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["hero_type", "hero_id"], name: "index_geneva_drive_workflows_on_hero_type_and_hero_id"
    t.index ["state"], name: "index_geneva_drive_workflows_on_state"
    t.index ["type", "hero_type", "hero_id"], name: "index_geneva_drive_workflows_unique_ongoing", unique: true, where: "state NOT IN ('finished', 'canceled') AND allow_multiple = 0"
    t.index ["type"], name: "index_geneva_drive_workflows_on_type"
  end

  create_table "item_events", force: :cascade do |t|
    t.integer "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.json "data", default: {}, null: false
    t.integer "item_id", null: false
    t.string "kind", null: false
    t.index ["actor_type", "actor_id"], name: "index_item_events_on_actor"
    t.index ["item_id", "created_at"], name: "index_item_events_on_item_id_and_created_at"
    t.index ["kind"], name: "index_item_events_on_kind"
  end

  create_table "items", force: :cascade do |t|
    t.float "actionability"
    t.string "actionability_band"
    t.float "anger_probability"
    t.string "author_email"
    t.string "author_handle"
    t.string "author_name"
    t.boolean "category_human_set", default: false, null: false
    t.integer "category_id"
    t.float "category_probability"
    t.datetime "claimed_at"
    t.integer "claimed_by_agent_id"
    t.datetime "created_at", null: false
    t.datetime "last_message_at", null: false
    t.datetime "last_reported_at"
    t.boolean "needs_review", default: false, null: false
    t.boolean "overdue", default: false, null: false
    t.string "permalink"
    t.boolean "product_human_set", default: false, null: false
    t.integer "product_id"
    t.float "product_probability"
    t.float "relevance_probability"
    t.boolean "relevant", default: true, null: false
    t.boolean "relevant_human_set", default: false, null: false
    t.string "sentiment"
    t.boolean "sentiment_human_set", default: false, null: false
    t.float "sentiment_probability"
    t.integer "source_id", null: false
    t.string "source_kind", null: false
    t.string "status", default: "new", null: false
    t.datetime "status_changed_at", null: false
    t.string "thread_key", null: false
    t.datetime "updated_at", null: false
    t.index ["actionability_band", "actionability"], name: "index_items_on_actionability_band_and_actionability"
    t.index ["category_id"], name: "index_items_on_category_id"
    t.index ["claimed_by_agent_id"], name: "index_items_on_claimed_by_agent_id"
    t.index ["last_message_at"], name: "index_items_on_last_message_at"
    t.index ["product_id"], name: "index_items_on_product_id"
    t.index ["sentiment"], name: "index_items_on_sentiment"
    t.index ["source_id"], name: "index_items_on_source_id"
    t.index ["source_kind", "thread_key"], name: "index_items_on_source_kind_and_thread_key", unique: true
    t.index ["status"], name: "index_items_on_status"
  end

  create_table "messages", force: :cascade do |t|
    t.float "anger_probability"
    t.string "author_role", default: "unknown", null: false
    t.boolean "backfilled", default: false, null: false
    t.text "body", default: "", null: false
    t.json "classification_answers"
    t.text "classification_error"
    t.datetime "classified_at"
    t.string "classifier_version"
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.integer "item_id", null: false
    t.datetime "occurred_at", null: false
    t.json "raw_payload", default: {}, null: false
    t.integer "source_id", null: false
    t.datetime "updated_at", null: false
    t.index ["item_id", "author_role"], name: "index_messages_on_item_id_and_author_role"
    t.index ["item_id", "created_at"], name: "index_messages_on_item_id_and_created_at"
    t.index ["item_id"], name: "index_messages_on_item_id"
    t.index ["source_id", "external_id"], name: "index_messages_on_source_id_and_external_id", unique: true
    t.index ["source_id"], name: "index_messages_on_source_id"
  end

  create_table "products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "digest_hour", default: 9, null: false
    t.float "escalation_threshold"
    t.json "hint_words", default: [], null: false
    t.string "name", null: false
    t.datetime "retired_at"
    t.string "slack_channel_id"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_products_on_name", unique: true
    t.index ["slug"], name: "index_products_on_slug", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.integer "anomaly_active_days", default: 7, null: false
    t.integer "anomaly_min_baseline_windows", default: 6, null: false
    t.integer "anomaly_min_count", default: 5, null: false
    t.float "anomaly_sensitivity", default: 3.0, null: false
    t.datetime "created_at", null: false
    t.float "escalation_threshold", default: 0.8, null: false
    t.float "low_confidence_threshold", default: 0.6, null: false
    t.integer "report_back_window_minutes", default: 240, null: false
    t.json "team_discord_role_ids", default: [], null: false
    t.json "team_discord_user_ids", default: [], null: false
    t.json "team_email_domains", default: ["every.to"], null: false
    t.datetime "updated_at", null: false
  end

  create_table "sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "default_product_id"
    t.string "kind", null: false
    t.text "last_error"
    t.datetime "last_error_at"
    t.datetime "last_message_at"
    t.string "month_key"
    t.decimal "month_spend", precision: 10, scale: 4, default: "0.0", null: false
    t.decimal "monthly_limit", precision: 10, scale: 4
    t.string "name", null: false
    t.string "public_token"
    t.string "selector", null: false
    t.text "signing_secret"
    t.string "since_id"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["default_product_id"], name: "index_sources_on_default_product_id"
    t.index ["kind", "selector"], name: "index_sources_on_kind_and_selector", unique: true
    t.index ["public_token"], name: "index_sources_on_public_token", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "every_user_id"
    t.string "name"
    t.string "password_digest"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["every_user_id"], name: "index_users_on_every_user_id", unique: true
  end

  create_table "webhook_deliveries", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "event", null: false
    t.integer "item_event_id"
    t.datetime "last_attempted_at"
    t.text "last_error"
    t.json "payload", default: {}, null: false
    t.integer "response_code"
    t.string "status", default: "pending", null: false
    t.boolean "test", default: false, null: false
    t.datetime "updated_at", null: false
    t.integer "webhook_endpoint_id", null: false
    t.index ["created_at"], name: "index_webhook_deliveries_on_created_at"
    t.index ["item_event_id"], name: "index_webhook_deliveries_on_item_event_id"
    t.index ["webhook_endpoint_id", "created_at"], name: "index_webhook_deliveries_on_webhook_endpoint_id_and_created_at"
  end

  create_table "webhook_endpoints", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.json "category_ids", default: [], null: false
    t.datetime "created_at", null: false
    t.json "events", default: [], null: false
    t.string "name", null: false
    t.json "product_ids", default: [], null: false
    t.text "secret", null: false
    t.json "sentiments", default: [], null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
  end

  add_foreign_key "anomalies", "products"
  add_foreign_key "anomalies", "sources"
  add_foreign_key "digests", "products"
  add_foreign_key "escalations", "items"
  add_foreign_key "escalations", "messages"
  add_foreign_key "escalations", "products"
  add_foreign_key "geneva_drive_step_executions", "geneva_drive_workflows", column: "workflow_id", on_delete: :cascade
  add_foreign_key "item_events", "items"
  add_foreign_key "items", "agents", column: "claimed_by_agent_id"
  add_foreign_key "items", "categories"
  add_foreign_key "items", "products"
  add_foreign_key "items", "sources"
  add_foreign_key "messages", "items"
  add_foreign_key "messages", "sources"
  add_foreign_key "sessions", "users"
  add_foreign_key "sources", "products", column: "default_product_id"
  add_foreign_key "webhook_deliveries", "item_events", on_delete: :nullify
  add_foreign_key "webhook_deliveries", "webhook_endpoints", on_delete: :cascade
end
