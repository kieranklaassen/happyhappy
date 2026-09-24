class User < ApplicationRecord
  # bcrypt silently truncates anything past 72 bytes, so a longer password would
  # authenticate on its first 72 bytes — reject it explicitly instead.
  MAXIMUM_PASSWORD_BYTES = 72
  MINIMUM_PASSWORD_LENGTH = 12

  # Every SSO users have no password, so presence is not required.
  has_secure_password validations: false
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :every_user_id, with: ->(id) { id.strip.presence }

  validates :email_address, presence: true, uniqueness: true
  validates :every_user_id, uniqueness: true, allow_nil: true
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH }, allow_nil: true
  validates :password, confirmation: true, allow_nil: true
  validate :password_within_bcrypt_limit

  private

  def password_within_bcrypt_limit
    return if password.blank?
    return if password.bytesize <= MAXIMUM_PASSWORD_BYTES

    errors.add(:password, "must be #{MAXIMUM_PASSWORD_BYTES} bytes or fewer")
  end
end
