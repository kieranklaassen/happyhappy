require "test_helper"

class DevLogin::SessionsControllerTest < ActionDispatch::IntegrationTest
  test "the dev login route does not exist in the test environment" do
    assert_not Rails.application.routes.url_helpers.respond_to?(:dev_login_path)
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/dev/login", method: :post)
    end
  end

  test "the dev login route is drawn only in development" do
    routes = File.read(Rails.root.join("config/routes.rb"))

    assert_match(/^\s*draw :dev_login if Rails\.env\.development\?$/, routes)
  end

  test "in development the dev login signs in a seeded every.to person" do
    person = User.create!(email_address: "dev@every.to", name: "Dev Person")

    as_development do
      assert_difference -> { person.sessions.count }, 1 do
        post "/dev/login", params: { email_address: "dev@every.to" }
      end

      assert_redirected_to root_url
      assert cookies[:session_id].present?
    end
  end

  test "in development the sign-in page lists the seeded people" do
    as_development do
      get new_session_path

      assert_inertia_component "auth/sign_in"
      assert_includes inertia.props[:dev_login_people], { "email" => "ana@every.to", "name" => "Ana Every" }
    end
  end

  test "in development an unknown person is sent back to the sign-in page" do
    as_development do
      assert_no_difference -> { Session.count } do
        post "/dev/login", params: { email_address: "nobody@every.to" }
      end

      assert_redirected_to new_session_url
    end
  end

  test "the action itself answers 404 outside development even when routed" do
    with_dev_login_routes do
      assert_no_difference -> { Session.count } do
        post "/dev/login", params: { email_address: users(:every_ana).email_address }
      end

      assert_response :not_found
    end
  end

  private

  def as_development
    original = Rails.env
    Rails.env = "development"
    with_dev_login_routes { yield }
  ensure
    Rails.env = original
  end

  def with_dev_login_routes
    with_routing do |set|
      set.draw_paths = [ Rails.root.join("config/routes") ]
      set.draw do
        resource :session, only: %i[new destroy]
        root "home#index"
        draw :dev_login
      end
      yield
    end
  end
end
