require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EVERY.TO ")
    assert_equal("downcased@every.to", user.email_address)
  end

  test "a user has no password" do
    user = User.create!(email_address: "sso@every.to", every_user_id: "every-user-sso", name: "SSO Person")

    assert user.persisted?
    assert_not user.respond_to?(:password=)
  end

  test "two users cannot share an every_user_id" do
    duplicate = User.new(email_address: "other@every.to", every_user_id: users(:every_ana).every_user_id)

    refute duplicate.valid?
    assert duplicate.errors.key?(:every_user_id)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "users without an every_user_id do not collide" do
    assert User.create!(email_address: "a@every.to").persisted?
    assert User.create!(email_address: "b@every.to").persisted?
  end

  test "every_email? is an exact, case-insensitive match on the normalized domain" do
    %w[ana@every.to ANA@EVERY.TO].push(" ana@every.to ").each do |email|
      assert User.every_email?(email), "#{email.inspect} should be an every.to address"
    end

    [ "ana@every.to.evil.com", "ana@sub.every.to", "ana@notevery.to", "@every.to", "every.to",
      "a@b@every.to", "someone@gmail.com", "", nil ].each do |email|
      refute User.every_email?(email), "#{email.inspect} should not be an every.to address"
    end
  end

  test "from_every_auth! creates, then updates by every_user_id" do
    user = User.from_every_auth!(uid: "every-1", email: "New@Every.to", name: "New", image: "")
    assert_equal [ "new@every.to", "New", nil ], [ user.email_address, user.name, user.avatar_url ]

    same = User.from_every_auth!(uid: "every-1", email: "new@every.to", name: "Renamed", image: "https://every.to/a.png")
    assert_equal user, same
    assert_equal [ "Renamed", "https://every.to/a.png" ], [ same.name, same.avatar_url ]
  end
end
