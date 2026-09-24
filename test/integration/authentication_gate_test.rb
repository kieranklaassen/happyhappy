require "test_helper"

# The session gate lives on InertiaController, so every page is gated by
# default; webhook endpoints and /mcp inherit from ActionController::Base
# (KTD5) and authenticate by provider signature or bearer token instead.
class AuthenticationGateTest < ActionDispatch::IntegrationTest
  class FeedStandInController < InertiaController
    def index = head(:ok)
  end

  class WebhookStandInController < ActionController::Base
    skip_forgery_protection

    def create = head(:ok)
  end

  test "an unauthenticated visit to a page redirects to sign-in, and a signed-in visit is served" do
    with_stand_in_routes do
      get "/items"
      assert_redirected_to new_session_url

      sign_in_as(users(:every_ana))
      get "/items"
      assert_response :ok
    end
  end

  test "Sign in with Every returns to the page that sent the visitor to sign in" do
    configure_every_oauth
    stub_every_token
    stub_every_userinfo
    https!

    with_stand_in_routes do
      get "/items"
      assert_redirected_to new_session_url

      get "/auth/every"
      state = Rack::Utils.parse_query(URI(response.location).query).fetch("state")
      get "/auth/every/callback", params: { code: "authorization-code", state: state }
      assert_redirected_to "https://www.example.com/items"
    end
  ensure
    restore_every_oauth
  end

  test "webhook and /mcp paths are not sent to sign-in" do
    with_stand_in_routes do
      post "/webhooks/slack"
      assert_response :ok

      post "/mcp"
      assert_response :ok
    end
  end

  test "the real webhook and /mcp endpoints answer unauthenticated requests themselves instead of redirecting" do
    host! "localhost"
    [ webhooks_slack_events_path, "/webhooks/intercom", postmark_webhook_path, mcp_path ].each do |path|
      post path, params: {}.to_json, headers: { "Content-Type" => "application/json" }

      assert_response :unauthorized, "#{path} should reject the unsigned request itself"
    end
  end

  test "the Every sign-in paths are public" do
    get new_session_path
    assert_response :success

    get "/auth/every/callback"
    assert_redirected_to new_session_url
  end

  private

  def with_stand_in_routes
    with_routing do |set|
      set.draw do
        resource :session, only: %i[new destroy]
        get "auth/every/callback", to: "sessions/every#create"
        get "items", to: "authentication_gate_test/feed_stand_in#index"
        post "webhooks/slack", to: "authentication_gate_test/webhook_stand_in#create"
        post "mcp", to: "authentication_gate_test/webhook_stand_in#create"
      end
      yield
    end
  end
end
