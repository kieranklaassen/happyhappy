require "test_helper"

class ResolveIncidentFromSlackJobTest < ActiveJob::TestCase
  include AnomalyHelper
  include SlackStubHelper

  setup do
    @incident = Incident.for_anomaly!(create_anomaly!)
  end

  test "does nothing when the incident does not exist" do
    ResolveIncidentFromSlackJob.perform_now(incident_id: 0, slack_user_id: "U0CUSTOMER", slack_user_name: "mara.writes")

    assert_empty slack_calls
  end

  test "does nothing when the incident is already resolved" do
    @incident.update!(status: :resolved, resolved_at: Time.current, resolved_by_name: "Ana Every")

    ResolveIncidentFromSlackJob.perform_now(incident_id: @incident.id, slack_user_id: "U0CUSTOMER", slack_user_name: "mara.writes")

    assert_empty slack_calls
    assert_equal "Ana Every", @incident.reload.resolved_by_name
  end

  test "resolves as the matching happyhappy user using case-insensitive Slack email" do
    stub_slack_method("users.info", {
      ok: true,
      user: { name: "ana.slack", profile: { email: "ANA@Every.TO", real_name: "Ana Slack" } }
    })

    ResolveIncidentFromSlackJob.perform_now(incident_id: @incident.id, slack_user_id: "U0ANA", slack_user_name: "ana.payload")

    assert_equal({ "user" => "U0ANA" }, slack_calls_to("users.info").sole)
    @incident.reload
    assert_predicate @incident, :resolved?
    assert_equal users(:every_ana), @incident.resolved_by
    assert_equal "Ana Every", @incident.resolved_by_name
  end

  test "falls back to Slack profile real_name when no user email matches" do
    stub_slack_method("users.info", {
      ok: true,
      user: { name: "mara.writes", profile: { email: "nobody@example.com", real_name: "Mara Lindqvist", display_name: "Mara" } }
    })

    ResolveIncidentFromSlackJob.perform_now(incident_id: @incident.id, slack_user_id: "U0CUSTOMER", slack_user_name: "mara.payload")

    @incident.reload
    assert_predicate @incident, :resolved?
    assert_nil @incident.resolved_by
    assert_equal "Mara Lindqvist", @incident.resolved_by_name
  end

  test "falls back to profile display_name when real_name is blank" do
    stub_slack_method("users.info", {
      ok: true,
      user: { name: "mara.writes", profile: { real_name: "  ", display_name: "Mara" } }
    })

    ResolveIncidentFromSlackJob.perform_now(incident_id: @incident.id, slack_user_id: "U0CUSTOMER", slack_user_name: "mara.payload")

    assert_nil @incident.reload.resolved_by
    assert_equal "Mara", @incident.resolved_by_name
  end

  test "falls back to Slack user name when profile names are blank or absent" do
    stub_slack_method("users.info", { ok: true, user: { name: "mara.writes", profile: { real_name: "", display_name: "" } } })

    ResolveIncidentFromSlackJob.perform_now(incident_id: @incident.id, slack_user_id: "U0CUSTOMER", slack_user_name: "mara.payload")

    assert_equal "mara.writes", @incident.reload.resolved_by_name

    second = Incident.for_anomaly!(create_anomaly!)
    stub_slack_method("users.info", { ok: true, user: { name: "no.profile" } })

    ResolveIncidentFromSlackJob.perform_now(incident_id: second.id, slack_user_id: "U0CUSTOMER", slack_user_name: "mara.payload")

    assert_equal "no.profile", second.reload.resolved_by_name
  end

  test "falls back to slack_user_name and then slack_user_id when Slack user info has no name" do
    stub_slack_method("users.info", { ok: true, user: { name: "", profile: {} } })

    ResolveIncidentFromSlackJob.perform_now(incident_id: @incident.id, slack_user_id: "U0CUSTOMER", slack_user_name: "mara.payload")
    assert_equal "mara.payload", @incident.reload.resolved_by_name

    second = Incident.for_anomaly!(create_anomaly!)
    ResolveIncidentFromSlackJob.perform_now(incident_id: second.id, slack_user_id: "U0FALLBACK", slack_user_name: "")
    assert_equal "U0FALLBACK", second.reload.resolved_by_name
  end

  test "skips users.info when slack_user_id is blank" do
    ResolveIncidentFromSlackJob.perform_now(incident_id: @incident.id, slack_user_id: "", slack_user_name: "mara.writes")

    assert_empty slack_calls
    @incident.reload
    assert_predicate @incident, :resolved?
    assert_nil @incident.resolved_by
    assert_equal "mara.writes", @incident.resolved_by_name
  end

  test "logs a warning and falls back to slack_user_name or slack_user_id on a permanent Slack error" do
    stub_slack_method("users.info", { ok: false, error: "missing_scope" })

    logs = capture_rails_logs do
      assert_no_enqueued_jobs(only: ResolveIncidentFromSlackJob) do
        ResolveIncidentFromSlackJob.perform_now(incident_id: @incident.id, slack_user_id: "U0CUSTOMER", slack_user_name: "mara.writes")
      end
    end

    assert_includes logs, "[slack] users.info failed for an incident resolve: Slack: missing_scope"
    @incident.reload
    assert_predicate @incident, :resolved?
    assert_nil @incident.resolved_by
    assert_equal "mara.writes", @incident.resolved_by_name

    second = Incident.for_anomaly!(create_anomaly!)
    capture_rails_logs do
      ResolveIncidentFromSlackJob.perform_now(incident_id: second.id, slack_user_id: "U0FALLBACK", slack_user_name: nil)
    end
    assert_equal "U0FALLBACK", second.reload.resolved_by_name
  end

  test "re-raises RetryableError so ActiveJob retries without resolving the incident" do
    stub_slack_method("users.info", { ok: false, error: "ratelimited" })
    args = { incident_id: @incident.id, slack_user_id: "U0CUSTOMER", slack_user_name: "mara.writes" }

    assert_enqueued_with(job: ResolveIncidentFromSlackJob, args: [ args ]) do
      ResolveIncidentFromSlackJob.perform_now(**args)
    end

    assert_predicate @incident.reload, :open?
  end

  test "re-raises RetryableError after exhausting retry attempts" do
    stub_slack_method("users.info", { ok: false, error: "ratelimited" })
    args = { incident_id: @incident.id, slack_user_id: "U0CUSTOMER", slack_user_name: "mara.writes" }

    ResolveIncidentFromSlackJob.perform_later(**args)
    assert_raises(Slack::Client::RetryableError) do
      5.times { perform_enqueued_jobs(only: ResolveIncidentFromSlackJob) }
    end

    assert_equal 5, slack_calls_to("users.info").size
    assert_predicate @incident.reload, :open?
  end

  private

  def capture_rails_logs
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end
end
