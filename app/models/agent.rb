class Agent < ApplicationRecord
  BROWSER_SUFFIX = "(WebMCP)"

  # A browser agent holds the claims a signed-in person makes over WebMCP (see ApplicationTool#agent).
  belongs_to :user, optional: true, inverse_of: :browser_agent
  has_many :claimed_items, class_name: "Item", foreign_key: :claimed_by_agent_id,
    inverse_of: :claimed_by_agent, dependent: :nullify
  has_many :events, class_name: "ItemEvent", as: :actor, dependent: :nullify

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, uniqueness: true
  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil) }

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  end

  # Builds an unsaved agent and returns it with its plaintext token, which is
  # never stored and cannot be recovered after this call.
  def self.issue(name:)
    token = "hh_#{SecureRandom.base58(40)}"
    [ new(name: name, token_digest: digest(token)), token ]
  end

  # The person's browser agent, created on first use. Its token is never shown, so it can only act through
  # the person's signed-in session.
  def self.browser_for(user)
    user.browser_agent || create_or_find_by!(user: user) do |agent|
      name = "#{user.name.presence || user.email_address} #{BROWSER_SUFFIX}"
      agent.name = exists?(name: name) ? "#{user.email_address} #{BROWSER_SUFFIX}" : name
      agent.token_digest = digest(SecureRandom.base58(40))
    end
  end

  # Who timeline events written by this agent are attributed to: the person for a browser agent.
  def event_actor
    user || self
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current) unless revoked?
  end
end
