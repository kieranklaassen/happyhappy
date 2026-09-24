# Module: ruby_llm

`ruby_llm` (~> 2.0) is a first-class default: a unified API over OpenAI,
Anthropic, and Gemini. It boots test-safe with no keys — each provider is simply
unavailable until a key is set.

## What this module is

- `config/initializers/ruby_llm.rb` reads keys from `ENV` first, then encrypted
  credentials (guarded so a missing master key never raises the boot).
- `default_model` defaults to `gemini-2.5-flash` (`RUBY_LLM_MODEL` to override);
  `request_timeout` defaults to 60s (`RUBY_LLM_REQUEST_TIMEOUT`).
- A `chat.ruby_llm` `ActiveSupport::Notifications` subscriber logs one structured
  line per completion (model, duration, tokens) into the normal Rails log.

## happyhappy delta from the template (ruby_llm 2.x)

The template still pins `ruby_llm ~> 1.16`. happyhappy moved to 2.x because
`ruby_llm-typesafe` (the TypeSafe Jev provider) requires `ruby_llm >= 2.0.0.rc3, < 3`.

- `config.model_registry_class` and `config.use_new_acts_as` are gone in 2.0
  (they only log a warning), so the initializer no longer sets them. In Rails the
  model registry reads the `ruby_llm_models` table when it exists and otherwise
  falls back to the bundled JSON catalog; happyhappy has no such table.
- 2.x only emits instrumentation events through `config.instrumenter`. Its
  Railtie sets that to `ActiveSupport::Notifications`, so the `chat.ruby_llm`
  subscriber keeps working unchanged.
- The CVE-2026-67991 bundler-audit ignore was removed: 2.0.0 stable carries the fix.
- `config/initializers/typesafe.rb` sets `typesafe_api_key` and the optional
  `typesafe_api_base` from `TYPESAFE_API_KEY` / `TYPESAFE_API_BASE`.

## Files (the module boundary)

- `Gemfile` — `gem "ruby_llm", "~> 2.0"` and `gem "ruby_llm-typesafe"`
- `config/initializers/ruby_llm.rb`, `config/initializers/typesafe.rb`
- `.env.example` — the `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` /
  `RUBY_LLM_MODEL` / `RUBY_LLM_REQUEST_TIMEOUT` / `TYPESAFE_API_KEY` placeholder names.
- `test/initializers/ruby_llm_test.rb`

## Adopt into an existing app

1. `bundle add ruby_llm --version "~> 2.0"`.
2. Copy `config/initializers/ruby_llm.rb` and the `.env.example` LLM entries.
3. Set at least one provider key in `ENV` or credentials to make a provider live.

## Verify adoption

- `bin/rails test test/initializers/ruby_llm_test.rb` (boots with no keys; the
  default model and timeout fall back correctly; the TypeSafe provider is
  registered; the notification subscriber logs).

## Opt-ins & non-adoptions

- **`leva`** (LLM eval harness) is an optional add-on. Add the gem and
  `mount Leva::Engine => "/leva"` in `config/routes.rb` when you need eval runs.
- **`rails_js_logger` is intentionally NOT used** — it does not exist as a
  maintained gem; frontend logging goes through the browser console / Vite.
