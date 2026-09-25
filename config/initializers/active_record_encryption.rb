# Webhook signing secrets are the one database-stored credential (KTD17), so
# Active Record encryption keys come from ENV. Generate a set with
# `bin/rails db:encryption:init`. Values already set by an environment file
# (test uses fixed dummy keys) win.
encryption = Rails.application.config.active_record.encryption
encryption.primary_key ||= ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
encryption.deterministic_key ||= ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
encryption.key_derivation_salt ||= ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
