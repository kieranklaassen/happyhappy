# Module: ruby_llm

`ruby_llm` (~> 1.16) is a first-class default: a unified API over OpenAI,
Anthropic, and Gemini. It boots test-safe with no keys — each provider is simply
unavailable until a key is set.

## What this module is

- `config/initializers/ruby_llm.rb` reads keys from `ENV` first, then encrypted
  credentials (guarded so a missing master key never raises the boot).
- `default_model` defaults to `gemini-2.5-flash` (`RUBY_LLM_MODEL` to override);
  `request_timeout` defaults to 60s (`RUBY_LLM_REQUEST_TIMEOUT`).
- `use_new_acts_as = true` + `model_registry_class = "Model"` for AR-backed chats.
- A `chat.ruby_llm` `ActiveSupport::Notifications` subscriber logs one structured
  line per completion (model, duration, tokens) into the normal Rails log.

## Files (the module boundary)

- `Gemfile` — `gem "ruby_llm", "~> 1.16"`
- `config/initializers/ruby_llm.rb`
- `.env.example` — the `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `GEMINI_API_KEY` /
  `RUBY_LLM_MODEL` / `RUBY_LLM_REQUEST_TIMEOUT` placeholder names.
- `test/initializers/ruby_llm_test.rb`

## Adopt into an existing app

1. `bundle add ruby_llm --version "~> 1.16"`.
2. Copy `config/initializers/ruby_llm.rb` and the `.env.example` LLM entries.
3. Set at least one provider key in `ENV` or credentials to make a provider live.

## Verify adoption

- `bin/rails test test/initializers/ruby_llm_test.rb` (boots with no keys; the
  default model and timeout fall back correctly; the notification subscriber logs).

## Opt-ins & non-adoptions

- **`leva`** (LLM eval harness) is an optional add-on. Add the gem and
  `mount Leva::Engine => "/leva"` in `config/routes.rb` when you need eval runs.
- **`rails_js_logger` is intentionally NOT used** — it does not exist as a
  maintained gem; frontend logging goes through the browser console / Vite.
