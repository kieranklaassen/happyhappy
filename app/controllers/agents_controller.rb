class AgentsController < InertiaController
  def index
    render inertia: "agents/index", props: { agents: agent_props, new_token: nil }
  end

  # Renders instead of redirecting so the plaintext token reaches the page once
  # and never passes through the session cookie or flash.
  def create
    agent, token = Agent.issue(name: params.expect(agent: [ :name ])[:name].to_s)

    if agent.save
      response.headers["Cache-Control"] = "no-store"
      render inertia: "agents/index", props: {
        agents: agent_props, new_token: { agent_id: agent.id, name: agent.name, token: token }
      }
    else
      redirect_to agents_path, inertia: { errors: agent.errors.to_hash(true).transform_values(&:first) }
    end
  end

  def revoke
    agent = Agent.find(params[:id])
    agent.revoke!
    redirect_to agents_path, notice: "#{agent.name} can no longer connect."
  end

  private

  def agent_props
    claim_counts = Item.where.not(claimed_by_agent_id: nil).group(:claimed_by_agent_id).count

    Agent.order(:name).map do |agent|
      {
        id: agent.id,
        name: agent.name,
        created_at: agent.created_at.iso8601,
        last_used_at: agent.last_used_at&.iso8601,
        revoked_at: agent.revoked_at&.iso8601,
        claimed_count: claim_counts.fetch(agent.id, 0)
      }
    end
  end
end
