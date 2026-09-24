require "test_helper"
require "erb"

class DeployConfigTest < ActiveSupport::TestCase
  DEPLOY_YML = Rails.root.join("config/deploy.yml")
  SECRETS = Rails.root.join(".kamal/secrets")
  DOCKERFILE = Rails.root.join("Dockerfile")
  DEPLOYING = Rails.root.join("DEPLOYING.md")

  # Every tenant-specific key the render requires (no defaults).
  REQUIRED_ENV = {
    "KAMAL_SERVICE" => "compound-stack",
    "KAMAL_IMAGE" => "ghcr.io/example/compound-stack",
    "KAMAL_WEB_HOST" => "203.0.113.10",
    "KAMAL_PROXY_HOST" => "compound-stack.example.test",
    "KAMAL_REGISTRY_USERNAME" => "example-user",
    "KAMAL_STORAGE_VOLUME" => "compound_stack_storage",
    "KAMAL_BUILDER_ARCH" => "amd64",
    "KAMAL_SSH_USER" => "deploy",
    "PUBLIC_BASE_URL" => "https://compound-stack.example.test",
    "EVERY_OAUTH_BASE_URL" => "https://every.example.test"
  }.freeze

  # Provider credentials the app reads from ENV (KTD4), delivered as Kamal secrets.
  APP_SECRETS = %w[
    RAILS_MASTER_KEY
    EVERY_OAUTH_CLIENT_ID
    EVERY_OAUTH_CLIENT_SECRET
    SLACK_SIGNING_SECRET
    SLACK_BOT_TOKEN
    DISCORD_BOT_TOKEN
    INTERCOM_CLIENT_SECRET
    POSTMARK_INBOUND_USER
    POSTMARK_INBOUND_PASSWORD
    X_BEARER_TOKEN
    TYPESAFE_API_KEY
  ].freeze

  def render_deploy(env)
    original = ENV.to_hash
    (REQUIRED_ENV.keys | env.keys | %w[APP_TIME_ZONE]).each { |k| ENV.delete(k) }
    ENV.update(env)
    ERB.new(File.read(DEPLOY_YML)).result(binding)
  ensure
    ENV.replace(original)
  end

  def secrets_entries
    File.readlines(SECRETS).map(&:strip).reject { |line| line.empty? || line.start_with?("#") }.to_h { |line| line.split("=", 2) }
  end

  test "renders to valid YAML reflecting the env under a full fixture env" do
    config = YAML.safe_load(render_deploy(REQUIRED_ENV))

    assert_equal REQUIRED_ENV["KAMAL_SERVICE"], config["service"]
    assert_equal REQUIRED_ENV["KAMAL_IMAGE"], config["image"]
    assert_includes config["servers"]["web"], REQUIRED_ENV["KAMAL_WEB_HOST"]
    assert_equal REQUIRED_ENV["KAMAL_PROXY_HOST"], config.dig("proxy", "host")
    assert_equal "/rails/public/vite", config["asset_path"]
    assert_equal "2.12.0", config["minimum_version"].to_s
  end

  test "renders a single discord role running bin/discord on the web host without a proxy" do
    config = YAML.safe_load(render_deploy(REQUIRED_ENV))
    discord = config.dig("servers", "discord")

    assert_equal [ REQUIRED_ENV["KAMAL_WEB_HOST"] ], discord["hosts"]
    assert_equal "bin/discord", discord["cmd"]
    assert_equal false, discord["proxy"]
    assert_equal [ "#{REQUIRED_ENV["KAMAL_STORAGE_VOLUME"]}:/rails/storage" ], config["volumes"],
      "the storage volume is global so web and discord share the SQLite databases"
  end

  test "passes every provider secret and the public settings to the containers" do
    env = YAML.safe_load(render_deploy(REQUIRED_ENV))["env"]

    assert_equal APP_SECRETS, env["secret"]
    assert_equal REQUIRED_ENV["PUBLIC_BASE_URL"], env.dig("clear", "PUBLIC_BASE_URL")
    assert_equal REQUIRED_ENV["EVERY_OAUTH_BASE_URL"], env.dig("clear", "EVERY_OAUTH_BASE_URL")
    assert_equal "UTC", env.dig("clear", "APP_TIME_ZONE")
  end

  test "APP_TIME_ZONE comes from the env and falls back to UTC when blank" do
    zone = ->(value) { YAML.safe_load(render_deploy(REQUIRED_ENV.merge("APP_TIME_ZONE" => value))).dig("env", "clear", "APP_TIME_ZONE") }

    assert_equal "Europe/Amsterdam", zone.call("Europe/Amsterdam")
    assert_equal "UTC", zone.call("")
  end

  test "fails loud (KeyError) when a required tenant key is missing" do
    assert_raises(KeyError) { render_deploy(REQUIRED_ENV.except("KAMAL_IMAGE")) }
  end

  test "fails loud (KeyError) when a required app setting is missing" do
    %w[PUBLIC_BASE_URL EVERY_OAUTH_BASE_URL].each do |key|
      assert_raises(KeyError, key) { render_deploy(REQUIRED_ENV.except(key)) }
    end
  end

  test "no resolved secret or hardcoded IP is committed to deploy.yml" do
    deploy = File.read(DEPLOY_YML)
    assert_no_match(/\b\d{1,3}(\.\d{1,3}){3}\b/, deploy, "deploy.yml must not hardcode an IP address")
    assert_no_match(/password:\s*\S*(key|token|secret)\S*/i, deploy)
  end

  test ".kamal/secrets uses shell indirection only, never a raw value" do
    File.foreach(SECRETS) do |line|
      stripped = line.strip
      next if stripped.empty? || stripped.start_with?("#")

      _key, value = stripped.split("=", 2)
      assert value&.start_with?("$"),
        "#{line.inspect} must resolve via shell indirection ($(...) or $VAR), not a raw secret"
    end
  end

  test ".kamal/secrets resolves every env secret deploy.yml lists" do
    listed = YAML.safe_load(render_deploy(REQUIRED_ENV)).dig("env", "secret")

    assert_empty listed - secrets_entries.keys, "every env.secret needs a line in .kamal/secrets"
    APP_SECRETS.excluding("RAILS_MASTER_KEY").each do |key|
      assert_equal "$#{key}", secrets_entries[key], "#{key} passes through from the deploy environment"
    end
  end

  test "DEPLOYING.md documents every secret, the provider URLs, and the X spending limit" do
    guide = File.read(DEPLOYING)

    (APP_SECRETS + %w[PUBLIC_BASE_URL EVERY_OAUTH_BASE_URL APP_TIME_ZONE]).each do |key|
      assert_includes guide, key
    end
    { "/auth/every/callback" => :get, "/webhooks/slack/events" => :post,
      "/webhooks/intercom" => :post, "/webhooks/postmark" => :post }.each do |path, method|
      assert_includes guide, path
      assert Rails.application.routes.recognize_path(path, method: method), "#{method} #{path} must be routed"
    end
    assert_match(/spending limit in the X developer console/i, guide)
  end

  test "Dockerfile exposes 80 and starts via thruster" do
    dockerfile = File.read(DOCKERFILE)
    assert_match(/^EXPOSE 80$/, dockerfile)
    assert_match(%r{CMD \["\./bin/thrust", "\./bin/rails", "server"\]}, dockerfile)
  end
end
