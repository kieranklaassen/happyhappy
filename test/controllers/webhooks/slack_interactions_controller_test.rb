require "test_helper"

class Webhooks::SlackInteractionsControllerTest < ActionDispatch::IntegrationTest
  include SlackEventsHelper
  include AnomalyHelper

  setup do
    @incident = Incident.for_anomaly!(create_anomaly!)
  end

  def click_payload(value: @incident.id.to_s, action_id: "incident_resolve", user: { id: "U0CUSTOMER", name: "mara.writes" })
    { type: "block_actions", user: user, actions: [ { action_id: action_id, value: value, type: "button" } ] }
  end

  def post_interaction(payload, secret: SIGNING_SECRET, timestamp: Time.current.to_i)
    body = URI.encode_www_form(payload: payload.to_json)
    headers = slack_signature_headers(body, secret: secret, timestamp: timestamp)
      .merge("Content-Type" => "application/x-www-form-urlencoded")
    with_slack_env do
      perform_enqueued_jobs(only: ResolveIncidentFromSlackJob) do
        post webhooks_slack_interactions_path, params: body, headers: headers
      end
    end
  end

  test "a signed Mark resolved click resolves as the happyhappy user with the Slack user's email" do
    users(:one).update!(email_address: "mara@example.com", name: "Mara")
    stub_slack_users_info

    post_interaction(click_payload)

    assert_response :ok
    @incident.reload
    assert_predicate @incident, :resolved?
    assert_equal users(:one), @incident.resolved_by
    assert_equal "Mara", @incident.resolved_by_name
  end

  test "a Slack user with no matching account is recorded by their Slack name" do
    stub_slack_users_info

    post_interaction(click_payload)

    assert_nil @incident.reload.resolved_by
    assert_equal "Mara Lindqvist", @incident.resolved_by_name
  end

  test "when users.info fails the click still resolves under the payload's name" do
    stub_slack_error("users.info", "missing_scope")

    post_interaction(click_payload)

    assert_equal "mara.writes", @incident.reload.resolved_by_name
  end

  test "a bad or stale signature is 401 and resolves nothing" do
    post_interaction(click_payload, secret: "wrong-secret")
    assert_response :unauthorized

    post_interaction(click_payload, timestamp: 6.minutes.ago.to_i)
    assert_response :unauthorized

    assert_predicate @incident.reload, :open?
  end

  test "other actions and unknown incidents are acknowledged and ignored" do
    post_interaction(click_payload(action_id: "something_else"))
    assert_response :ok
    post_interaction(click_payload(value: "0"))
    assert_response :ok

    assert_predicate @incident.reload, :open?
  end
end
