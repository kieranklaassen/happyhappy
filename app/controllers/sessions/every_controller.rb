# The app side of the OmniAuth `every` strategy: `create` receives a verified
# callback, `failure` every other outcome (OmniAuth.config.on_failure).
class Sessions::EveryController < InertiaController
  allow_unauthenticated_access

  FAILURE_MESSAGES = {
    "every_oauth_unconfigured" => "Sign in with Every is not configured on this server."
  }.freeze
  DEFAULT_FAILURE_MESSAGE = "Sign in with Every did not complete. Try again."

  def create
    clear_state_cookie
    auth = request.env["omniauth.auth"]
    return failure if auth.nil?
    return refuse(auth.info.email) unless every_person?(auth)

    user = User.from_every_auth!(uid: auth.uid, email: auth.info.email, name: auth.info.name, image: auth.info.image)
    start_new_session_for user
    redirect_to after_authentication_url
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("every sign-in could not save the user: #{e.record.errors.full_messages.to_sentence}")
    redirect_to new_session_path, alert: DEFAULT_FAILURE_MESSAGE
  end

  def failure
    clear_state_cookie
    error_type = request.env["omniauth.error.type"].to_s
    Rails.logger.info("every sign-in failed: #{error_type}")
    redirect_to new_session_path, alert: FAILURE_MESSAGES.fetch(error_type, DEFAULT_FAILURE_MESSAGE)
  end

  private

  # Every's UserInfo carries no email_verified claim today: an Every account's
  # address is the one it signs in with. An explicit false is still refused.
  def every_person?(auth)
    User.every_email?(auth.info.email) && auth.extra.raw_info["email_verified"] != false
  end

  def refuse(email)
    render inertia: "auth/refused", props: { email: email.to_s.strip }, status: :forbidden
  end

  def clear_state_cookie
    cookies.delete(OmniAuth::Strategies::Every::STATE_COOKIE, path: "/", secure: true)
  end
end
