class IncidentsController < InertiaController
  before_action :set_incident

  def show
    render inertia: "incidents/show", props: { incident: @incident.to_props }
  end

  def resolve
    result = Incidents::Resolve.call(incident: @incident, actor: Current.user, note: params[:note],
      handle_items: params[:handle_items])
    if result.success?
      redirect_to incident_path(@incident), notice: "Incident resolved."
    else
      redirect_to incident_path(@incident), alert: result.error
    end
  end

  private

  def set_incident
    @incident = Incident.includes(:product, anomalies: %i[product source]).find(params[:id])
  end
end
