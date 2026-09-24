# frozen_string_literal: true

require "test_helper"

class RubyLlmInitializerTest < ActiveSupport::TestCase
  test "the app boots with the ruby_llm initializer loaded and no API keys set" do
    # If the initializer raised on a missing key/credential, boot would have
    # failed and this suite would not run. Assert it configured successfully.
    assert RubyLLM.config.default_model.present?
  end

  test "RUBY_LLM_MODEL unset resolves default_model to the gemini fallback" do
    assert_nil ENV["RUBY_LLM_MODEL"]
    assert_equal "gemini-2.5-flash", RubyLLM.config.default_model
  end

  test "request_timeout falls back to 60 seconds" do
    assert_equal 60, RubyLLM.config.request_timeout
  end

  test "runs on ruby_llm 2.x with the TypeSafe provider registered and no key" do
    assert_operator Gem::Version.new(RubyLLM::VERSION), :>=, Gem::Version.new("2.0.0")
    assert_equal RubyLLM::Providers::TypeSafe, RubyLLM::Provider.providers[:typesafe]
    assert_nil RubyLLM.config.typesafe_api_key
  end

  test "chat events reach ActiveSupport::Notifications" do
    assert_equal ActiveSupport::Notifications, RubyLLM.config.instrumenter
  end

  test "the chat.ruby_llm notification subscriber logs without raising" do
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)

    assert_nothing_raised do
      ActiveSupport::Notifications.instrument("chat.ruby_llm", model: "test-model", total_tokens: 42) { :ok }
    end

    assert_match(/\[ruby_llm\] chat model=test-model/, io.string)
  ensure
    Rails.logger = original
  end
end
