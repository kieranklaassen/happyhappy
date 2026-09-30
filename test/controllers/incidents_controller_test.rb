require "test_helper"

class IncidentsControllerTest < ActionDispatch::IntegrationTest
  include AnomalyHelper

  setup do
    sign_in_as users(:every_ana)
    @anomaly = create_anomaly!(source: sources(:intercom_inbox))
    @incident = Incident.for_anomaly!(@anomaly)
  end

  test "shows the incident with its anomalies, sources, and driving items" do
    get incident_path(@incident)

    assert_response :success
    assert_inertia_component "incidents/show"
    props = inertia.props[:incident]
    assert_equal "open", props["status"]
    assert_equal [ @anomaly.id ], props["anomalies"].pluck("id")
    assert_equal @incident.id, props["anomalies"].first["incident_id"]
    assert_includes props["sources"].pluck("name"), sources(:intercom_inbox).name
    assert_equal [ items(:angry_slack).id ], props["item_ids"]
  end

  test "resolve records the person and the note, and can mark the driving items handled" do
    patch resolve_incident_path(@incident), params: { note: "Support caught up", handle_items: "1" }

    assert_redirected_to incident_path(@incident)
    assert_equal "Incident resolved.", flash[:notice]
    @incident.reload
    assert_predicate @incident, :resolved?
    assert_equal users(:every_ana), @incident.resolved_by
    assert_equal "Support caught up", @incident.resolution_note
    assert items(:angry_slack).reload.status_handled?
  end

  test "resolve without the checkbox leaves items alone, and resolving twice is an alert" do
    patch resolve_incident_path(@incident), params: { note: "" }
    assert_nil @incident.reload.resolution_note
    assert items(:angry_slack).reload.status_new?

    patch resolve_incident_path(@incident)
    assert_equal "Incident #{@incident.id} is already resolved.", flash[:alert]
  end

  test "resolved anomalies leave the dashboard callouts and the feed banner" do
    patch resolve_incident_path(@incident)

    get root_path
    assert_nil inertia.props[:anomalies][products(:cora).slug]
    get items_path
    assert_empty inertia.props[:anomalies]
  end

  test "signed-out visitors are sent to sign in" do
    sign_out
    get incident_path(@incident)

    assert_redirected_to new_session_path
  end
end
