module SlackEventsHelper
  SIGNING_SECRET = "slack-test-signing-secret"
  API = "https://slack.com/api"

  def slack_payload(name, event: {}, **envelope)
    payload = JSON.parse(file_fixture("slack/#{name}.json").read)
    payload["event"]&.merge!(event.deep_stringify_keys)
    payload.merge(envelope.deep_stringify_keys)
  end

  def slack_signature_headers(body, secret: SIGNING_SECRET, timestamp: Time.current.to_i)
    digest = OpenSSL::HMAC.hexdigest("SHA256", secret, "v0:#{timestamp}:#{body}")
    {
      "Content-Type" => "application/json",
      "X-Slack-Request-Timestamp" => timestamp.to_s,
      "X-Slack-Signature" => "v0=#{digest}"
    }
  end

  def stub_slack_users_info(fixture: "users_info")
    stub_request(:post, "#{API}/users.info")
      .to_return(body: file_fixture("slack/#{fixture}.json").read, headers: { "Content-Type" => "application/json" })
  end

  def stub_slack_permalink
    recorded = JSON.parse(file_fixture("slack/chat_get_permalink.json").read)
    stub_request(:post, "#{API}/chat.getPermalink").to_return do |request|
      params = URI.decode_www_form(request.body).to_h
      permalink = "https://every-community.slack.com/archives/#{params["channel"]}/p#{params["message_ts"].delete(".")}"
      { body: recorded.merge("channel" => params["channel"], "permalink" => permalink).to_json,
        headers: { "Content-Type" => "application/json" } }
    end
  end

  def stub_slack_error(method, error)
    stub_request(:post, "#{API}/#{method}")
      .to_return(body: { ok: false, error: error }.to_json, headers: { "Content-Type" => "application/json" })
  end

  def with_slack_env(signing_secret: SIGNING_SECRET, bot_token: "xoxb-test-token")
    previous = ENV.to_h.slice("SLACK_SIGNING_SECRET", "SLACK_BOT_TOKEN")
    ENV["SLACK_SIGNING_SECRET"] = signing_secret
    ENV["SLACK_BOT_TOKEN"] = bot_token
    yield
  ensure
    %w[SLACK_SIGNING_SECRET SLACK_BOT_TOKEN].each { |key| ENV[key] = previous[key] }
  end
end
