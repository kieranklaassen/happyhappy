require "test_helper"

class Webhooks::IntercomControllerTest < ActionDispatch::IntegrationTest
  include IntercomPayloads

  SECRET = "intercom-test-client-secret"

  setup do
    @previous_secret = ENV["INTERCOM_CLIENT_SECRET"]
    ENV["INTERCOM_CLIENT_SECRET"] = SECRET
  end

  teardown do
    ENV["INTERCOM_CLIENT_SECRET"] = @previous_secret
  end

  test "HEAD validation returns 200 without a signature" do
    head "/webhooks/intercom"

    assert_response :ok
  end

  test "a signed conversation.user.created creates an item keyed by conversation id" do
    assert_difference -> { Item.count } => 1, -> { Message.count } => 1 do
      deliver intercom_created.to_json
    end

    assert_response :ok
    item = Item.find_by!(source_kind: "intercom", thread_key: "215470000000777")
    assert_equal sources(:intercom_inbox), item.source
  end

  test "covers AE5 ingest half: three signed replies add three messages to one item" do
    deliver intercom_created.to_json

    assert_difference -> { Item.count } => 0, -> { Message.count } => 3 do
      %w[r-1 r-2 r-3].each do |part_id|
        deliver intercom_replied(id: part_id, body: "<p>Angry reply #{part_id}</p>").to_json
        assert_response :ok
      end
    end
  end

  test "a bad signature returns 401 and stores nothing" do
    assert_no_difference -> { Message.count } do
      deliver intercom_created.to_json, signature: "sha1=#{"0" * 40}"
    end

    assert_response :unauthorized
  end

  test "a missing signature returns 401" do
    post "/webhooks/intercom", params: intercom_created.to_json, headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "without a configured client secret every delivery is rejected" do
    body = intercom_created.to_json
    signature = sign(body)
    ENV["INTERCOM_CLIENT_SECRET"] = nil

    deliver body, signature: signature

    assert_response :unauthorized
  end

  test "the signature covers the raw body byte for byte" do
    body = JSON.pretty_generate(intercom_created)

    deliver body, signature: sign(intercom_created.to_json)

    assert_response :unauthorized
  end

  test "an admin reply is acknowledged and ignored" do
    assert_no_difference -> { Message.count } do
      deliver intercom_replied(author_type: "admin").to_json
    end

    assert_response :ok
  end

  test "a signed ping is acknowledged" do
    deliver({ type: "notification_event", topic: "ping", data: { item: { message: "ping" } } }.to_json)

    assert_response :ok
  end

  test "a signed body that is not JSON returns 400" do
    deliver "not json".dup

    assert_response :bad_request
  end

  private

  def deliver(body, signature: sign(body))
    post "/webhooks/intercom", params: body,
      headers: { "Content-Type" => "application/json", "X-Hub-Signature" => signature }
  end

  def sign(body)
    "sha1=#{OpenSSL::HMAC.hexdigest("SHA1", SECRET, body)}"
  end
end
