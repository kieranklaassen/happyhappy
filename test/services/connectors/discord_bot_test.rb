require "test_helper"
require "open3"

class Connectors::DiscordBotTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @logger = ActiveSupport::Logger.new(StringIO.new)
    @bot = Connectors::DiscordBot.new(token: "test-token", logger: @logger)
  end

  test "requests guild messages together with the message content intent" do
    intents = @bot.instance_variable_get(:@bot).instance_variable_get(:@intents)

    assert_equal 1 << 15, intents & (1 << 15)
    assert_equal Discordrb::INTENTS[:server_messages], intents & Discordrb::INTENTS[:server_messages]
    assert_equal Discordrb::INTENTS[:servers], intents & Discordrb::INTENTS[:servers]
  end

  test "a message create event is ingested" do
    assert_difference -> { Message.count } => 1 do
      @bot.handle_message(JSON.parse(file_fixture("discord/message_create.json").read))
    end
  end

  test "a failed ingest records the error on the channel's source" do
    payload = JSON.parse(file_fixture("discord/message_create.json").read).merge("timestamp" => nil, "id" => nil)

    assert_no_difference -> { Message.count } do
      @bot.handle_message(payload)
    end

    assert_match "ActiveModel::ValidationError", sources(:discord_spiral).reload.last_error
  end

  test "bin/discord exits cleanly with a clear message when the token is missing" do
    output, status = Open3.capture2e({ "DISCORD_BOT_TOKEN" => nil }, Rails.root.join("bin/discord").to_s)

    assert status.success?
    assert_match "DISCORD_BOT_TOKEN is not set", output
  end

  test "disconnect and reconnect update Discord source health" do
    @bot.handle_disconnected
    assert_equal "Discord gateway: disconnected, reconnecting", sources(:discord_spiral).reload.last_error

    @bot.handle_connected
    assert_nil sources(:discord_spiral).reload.last_error
  end
end
