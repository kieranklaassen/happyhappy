class SessionsController < InertiaController
  allow_unauthenticated_access only: :new

  def new
    render inertia: "auth/sign_in", props: {
      dev_login_people: (DevLogin::SessionsController.people if Rails.env.development?)
    }.compact
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
