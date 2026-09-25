class User < ApplicationRecord
  include EveryIdentity

  has_many :sessions, dependent: :destroy
  has_one :browser_agent, class_name: "Agent", dependent: :nullify, inverse_of: :user

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :every_user_id, with: ->(id) { id.strip.presence }

  validates :email_address, presence: true, uniqueness: true
end
