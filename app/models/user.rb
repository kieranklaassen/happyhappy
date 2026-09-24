class User < ApplicationRecord
  include EveryIdentity

  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :every_user_id, with: ->(id) { id.strip.presence }

  validates :email_address, presence: true, uniqueness: true
end
