# frozen_string_literal: true

class SettingsController < InertiaController
  def show
    render inertia: "settings/edit", props: {
      setting: Setting.current.slice(:low_confidence_threshold, :escalation_threshold, :report_back_window_minutes,
        :team_email_domains, :team_discord_role_ids, :team_discord_user_ids)
    }
  end

  def update
    setting = Setting.current
    if setting.update(params.expect(setting: %i[low_confidence_threshold escalation_threshold report_back_window_minutes
      team_email_domains team_discord_role_ids team_discord_user_ids]))
      redirect_to settings_path, notice: "Settings saved."
    else
      redirect_to settings_path, inertia: { errors: setting.errors }
    end
  end
end
