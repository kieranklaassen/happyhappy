module Backfill
  # One-time catch-up for Intercom items created before happyhappy mirrored the
  # conversation state (Connectors::Intercom.sync_state): searches every closed
  # or snoozed conversation updated since the oldest open item, applies that
  # state, and records the rest as open. Closing marks an unresolved item
  # handled, as backfill so it sends no outbound webhooks. Also fills the author
  # email of items whose only identity is an email address typed into Fin.
  #
  #   Backfill::IntercomStates.new.call
  #   # => { searched: 6605, closed: 3650, snoozed: 3, open: 30, unchanged: 0, emails: 1 }
  class IntercomStates < Intercom
    def initialize(token: ENV["INTERCOM_ACCESS_TOKEN"], sleeper: nil)
      oldest = Item.where(source_kind: Source.kinds[:intercom]).unresolved.minimum(:last_message_at) || Time.current
      super(since: oldest - 1.day, token: token, sleeper: sleeper)
    end

    def call
      states = remote_states
      counts = Hash.new(0).merge(searched: states.size)
      Item.where(source_kind: Source.kinds[:intercom]).unresolved.find_each do |item|
        state = states.fetch(item.thread_key, "open")
        outcome = Connectors::Intercom.apply_state(item, state, backfill: true)
        counts[outcome == :closed ? :closed : (outcome ? state.to_sym : :unchanged)] += 1
      end
      counts[:emails] = fill_typed_emails
      counts
    end

    private

    def remote_states
      states = {}
      starting_after = nil
      loop do
        page = @http.post("/conversations/search", {
          query: { operator: "AND", value: [
            { field: "updated_at", operator: ">", value: @since.to_i },
            { field: "state", operator: "IN", value: %w[closed snoozed] }
          ] },
          pagination: { per_page: PAGE_SIZE, starting_after: starting_after }.compact
        })
        page.fetch("conversations", []).each { |conversation| states[conversation["id"].to_s] = conversation["state"] }
        starting_after = page.dig("pages", "next", "starting_after")
        break if starting_after.blank?
      end
      states
    end

    def fill_typed_emails
      Item.where(source_kind: Source.kinds[:intercom], author_email: nil, author_name: nil, author_handle: nil).find_each.count do |item|
        email = item.messages.from_customers.map { |message| message.body.to_s.strip.delete_prefix("mailto:") }
          .find { |body| body.match?(Message::EMAIL_ONLY) }
        email && item.update!(author_email: email)
      end
    end
  end
end
