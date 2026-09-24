class Agent < ApplicationRecord
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

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current) unless revoked?
  end
end
