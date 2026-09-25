require "test_helper"

class SourceTest < ActiveSupport::TestCase
  test "supports the six source kinds" do
    assert_equal %w[slack discord intercom email x custom], Source.kinds.keys
  end

  test "a custom source generates its public token, selector, and encrypted signing secret" do
    source = Source.create!(kind: "custom", name: "Spiral app", selector: "", default_product: products(:spiral))

    assert_match(/\A[1-9A-HJ-NP-Za-km-z]{24}\z/, source.public_token)
    assert_equal source.public_token, source.selector
    assert_match(/\Ahhsec_[1-9A-HJ-NP-Za-km-z]{40}\z/, source.signing_secret)
    assert source.encrypted_attribute?(:signing_secret)
    stored = Source.connection.select_value("SELECT signing_secret FROM sources WHERE id = #{source.id}")
    assert_not_includes stored, source.signing_secret
  end

  test "a custom source keeps its token when the selector is edited" do
    source = sources(:cora_app_webhook)

    source.update!(selector: "something-else")

    assert_equal "cora-app-webhook-token", source.reload.selector
  end

  test "a custom source needs a product" do
    source = Source.new(kind: "custom", name: "No product", selector: "")

    refute source.valid?
    assert source.errors.key?(:default_product_id)
  end

  test "rotating the signing secret replaces it" do
    source = sources(:cora_app_webhook)

    source.rotate_signing_secret!

    assert_not_equal "hhsec_cora-app-test-secret", source.reload.signing_secret
    assert_match(/\Ahhsec_/, source.signing_secret)
  end

  test "other kinds get no webhook credentials" do
    source = Source.create!(kind: "slack", name: "Slack #sparkle", selector: "C0SPARKLE")

    assert_nil source.public_token
    assert_nil source.signing_secret
  end

  test "rejects an unknown kind" do
    source = Source.new(kind: "reddit", name: "r/every", selector: "every")

    refute source.valid?
    assert source.errors.key?(:kind)
  end

  test "selector is unique per kind" do
    duplicate = Source.new(kind: "slack", name: "Copy", selector: " C0COMMUNITY ")

    refute duplicate.valid?
    assert Source.new(kind: "discord", name: "Other", selector: "C0COMMUNITY").valid?
  end

  test "a source with no default product is allowed" do
    source = Source.new(kind: "intercom", name: "Catch-all", selector: "*")

    assert source.valid?, source.errors.full_messages.to_sentence
  end

  test "for finds a source by kind and selector" do
    assert_equal sources(:slack_community), Source.for(:slack, "C0COMMUNITY")
    assert_nil Source.for(:discord, "C0COMMUNITY")
  end

  test "recording a message updates last message time and clears the error" do
    source = sources(:lex_legacy)
    refute source.healthy?

    freeze_time do
      source.record_message_received!
      assert_equal Time.current, source.reload.last_message_at
    end
    assert_nil source.last_error
    assert source.healthy?
  end

  test "recording an error keeps the message and time" do
    source = sources(:slack_community)

    source.record_error!(RuntimeError.new("gateway closed"))

    assert_equal "RuntimeError: gateway closed", source.reload.last_error
    assert source.last_error_at.present?
  end

  test "X sources carry budget state" do
    source = sources(:x_budget_paused)

    assert source.paused_for_budget?
    assert_equal 10, source.monthly_limit
    assert_equal 10, source.month_spend
  end
end
