require "test_helper"

class Messages::AuthorRoleTest < ActiveSupport::TestCase
  test "an author email on a team domain is team, whatever the source" do
    assert_equal "team", role("intercom", { "part" => { "author" => { "type" => "user", "email" => "Kate@Every.to" } } })
    assert_equal "team", role("email", {}, author_email: "kieran@every.to")
    assert_equal "team", role("custom", { "author" => { "email" => "dan@every.to" } })
    assert_equal "customer", role("email", {}, author_email: "ana@example.com")
  end

  test "Intercom admins and bots are team; users, leads, and contacts are customers" do
    assert_equal "team", role("intercom", intercom("admin"))
    assert_equal "team", role("intercom", intercom("bot"))
    %w[user lead contact].each { |type| assert_equal "customer", role("intercom", intercom(type)) }
    assert_equal "unknown", role("intercom", {})
  end

  test "Discord authors holding a team role or on the team list are team; other members are customers" do
    Setting.current.update!(team_discord_role_ids: [ "797" ], team_discord_user_ids: [ "42" ])

    assert_equal "team", role("discord", discord("7", roles: [ "1", "797" ]))
    assert_equal "team", role("discord", discord("42"))
    assert_equal "customer", role("discord", discord("7", roles: [ "1" ]))
    assert_equal "unknown", role("discord", discord("7"))
  end

  test "X authors are customers and sources without author metadata are unknown" do
    assert_equal "customer", role("x", {})
    assert_equal "unknown", role("slack", { "user" => "U1" })
  end

  test "a changed team domain list takes effect" do
    Setting.current.update!(team_email_domains: "every.to, @cora.computer")

    assert_equal "team", role("email", {}, author_email: "help@cora.computer")
  end

  private

  def role(kind, payload, author_email: nil)
    Messages::AuthorRole.call(source_kind: kind, raw_payload: payload, author_email: author_email)
  end

  def intercom(type)
    { "part" => { "author" => { "type" => type, "email" => "someone@example.com" } } }
  end

  def discord(id, roles: nil)
    { "author" => { "id" => id } }.merge(roles ? { "member" => { "roles" => roles } } : {})
  end
end
