# frozen_string_literal: true

class SettingsController < InertiaController
  FIELDS = %i[
    low_confidence_threshold escalation_threshold report_back_window_minutes
    anomaly_sensitivity anomaly_min_count anomaly_min_baseline_windows anomaly_active_days
    team_email_domains team_discord_role_ids team_discord_user_ids
    slack_channel_id digest_time_zone digest_hour
  ].freeze

  def show
    render inertia: "settings/edit", props: {
      setting: Setting.current.slice(*FIELDS),
      time_zones: ActiveSupport::TimeZone.all.map { |zone| zone.tzinfo.name }.uniq.sort
    }
  end

  def update
    setting = Setting.current
    if setting.update(params.expect(setting: FIELDS))
      redirect_to settings_path, notice: "Settings saved."
    else
      redirect_to settings_path, inertia: { errors: setting.errors }
    end
  end
end
