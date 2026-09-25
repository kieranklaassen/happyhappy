# frozen_string_literal: true

# TypeSafe (Jev) classifies every message. Optional at boot: with no key the
# provider is simply unavailable, and tests use the fake classifier instead.
# RubyLLM stores blank values as nil, so unset variables fall back cleanly.
RubyLLM.configure do |config|
  config.typesafe_api_key = ENV["TYPESAFE_API_KEY"]
  config.typesafe_api_base = ENV["TYPESAFE_API_BASE"]
end
