module Messages
  # Decides from provider metadata whether a customer or Every's own team wrote a
  # message:
  #
  # - any author email on a team domain (Setting#team_email_domains) is team
  # - Intercom admins and bots are team; users, leads, and contacts are customers
  # - a Discord author on the team user list, or holding a team server role, is
  #   team; a member without one is a customer
  # - email and X authors are customers
  #
  # Returns "unknown" when the metadata cannot tell, such as a Discord message
  # with no member roles; the classifier then asks Jev (Classification::Apply).
  #
  #   Messages::AuthorRole.call(source_kind: "intercom", raw_payload: payload) # => "customer"
  class AuthorRole
    INTERCOM_TEAM_TYPES = %w[admin bot team].freeze
    INTERCOM_CUSTOMER_TYPES = %w[user lead contact].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(source_kind:, raw_payload:, author_email: nil, setting: Setting.current)
      @source_kind = source_kind.to_s
      @payload = raw_payload.is_a?(Hash) ? raw_payload : {}
      @author_email = author_email
      @setting = setting
    end

    def call
      return "team" if team_email?

      case @source_kind
      when "intercom" then intercom
      when "discord" then discord
      when "email", "x" then "customer"
      else "unknown"
      end
    end

    private

    def intercom
      type = @payload.dig("part", "author", "type")
      if INTERCOM_TEAM_TYPES.include?(type) then "team"
      elsif INTERCOM_CUSTOMER_TYPES.include?(type) then "customer"
      else "unknown"
      end
    end

    def discord
      author_id = @payload.dig("author", "id").to_s
      roles = @payload.dig("member", "roles")
      if Array(@setting.team_discord_user_ids).map(&:to_s).include?(author_id) then "team"
      elsif !roles.is_a?(Array) then "unknown"
      elsif roles.map(&:to_s).intersect?(Array(@setting.team_discord_role_ids).map(&:to_s)) then "team"
      else "customer"
      end
    end

    def team_email?
      domains = Array(@setting.team_email_domains).map { |domain| domain.to_s.strip.downcase.delete_prefix("@") }.compact_blank
      emails.any? { |email| domains.include?(email.split("@", 2).last) }
    end

    def emails
      author = @payload["author"].is_a?(Hash) ? @payload["author"] : {}
      [ @author_email, @payload.dig("part", "author", "email"), @payload.dig("FromFull", "Email"), author["email"] ]
        .filter_map { |email| email.to_s.strip.downcase.presence if email.to_s.include?("@") }
    end
  end
end
