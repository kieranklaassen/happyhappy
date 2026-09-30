module Slack
  # Slack IDs a product pings about incidents: users (U..., or W... on Enterprise Grid) and user
  # groups (S...). Display names cannot be mentioned by a bot, so only IDs are accepted.
  #
  #   Slack::Mentions.render(%w[U0AGQDHRV8U S0BINGSU01]) # => "<@U0AGQDHRV8U> <!subteam^S0BINGSU01>"
  module Mentions
    ID = /\A[UWS][A-Z0-9]{6,}\z/

    module_function

    def render(ids)
      ids.grep(ID).map { |id| id.start_with?("S") ? "<!subteam^#{id}>" : "<@#{id}>" }.join(" ")
    end
  end
end
