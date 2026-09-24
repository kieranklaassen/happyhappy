# Module: auth

Database-backed session authentication built on the Rails 8 `authentication`
generator, with Sign in with Every as the only production login. No passwords
and no open registration: a user row is created by the first Every sign-in of a
verified every.to address, or ahead of it by `bin/rails users:create`.

## What this module is

- A DB-backed `Session` model; the signed, permanent `session_id` cookie
  (`httponly`, `same_site: :lax`) is the only credential a browser carries.
- The gate lives on `InertiaController` (default-on), so **every Inertia page is
  authenticated unless it opts out** with `allow_unauthenticated_access`.
  Framework endpoints (e.g. `/up`), provider webhooks, and `/mcp` inherit from
  `ActionController::Base` and authenticate on their own terms.
- One session writer, `Authentication#start_new_session_for`, used by the Every
  callback and the dev login alike; it replaces any session the browser already
  had.
- **Sign in with Every** (`lib/omniauth/strategies/every.rb`), ported from Baby
  Agent's legacy mode: authorization code with scope `basic_profile`, identity
  from `GET /oauth/userinfo`. The state lives in the encrypted session and in a
  `__Host-every_state` nonce cookie the callback must echo; a transaction older
  than ten minutes fails closed. `GET /auth/every` starts it (a top-level link,
  so GET is allowed).
- **The every.to gate** (`Sessions::EveryController#create`): only an address
  whose normalized domain is exactly `every.to` signs in (`User.every_email?`);
  anyone else gets the `auth/refused` page (403) and no user or session. Every's
  UserInfo carries no `email_verified` claim, so the address Every returns is
  trusted; an explicit `email_verified: false` is refused. Users are upserted by
  `every_user_id` (`User.from_every_auth!`), and name, email, and avatar follow
  Every on each sign-in.
- **Dev login** (development only): the sign-in page lists every user and one
  click posts to `/dev/login`. The route is drawn only when
  `Rails.env.development?` (`config/routes/dev_login.rb`) and the action answers
  404 elsewhere. `bin/rails db:seed` adds `dev@every.to` and `support@every.to`
  in development.

## Files (the module boundary)

- `app/models/user.rb`, `app/models/user/every_identity.rb`: email normalization, the Every identity, the every.to rule.
- `app/models/session.rb`, `app/models/current.rb`
- `app/controllers/concerns/authentication.rb`: the gate + session lifecycle.
- `app/controllers/inertia_controller.rb`: `include Authentication` (gate default-on).
- `app/controllers/sessions_controller.rb`: the sign-in page and sign-out.
- `app/controllers/sessions/every_controller.rb`, `lib/omniauth/strategies/every.rb`, `config/initializers/omniauth.rb`: Sign in with Every.
- `app/controllers/dev_login/sessions_controller.rb`, `config/routes/dev_login.rb`: the dev login.
- `app/frontend/pages/auth/sign_in.tsx`, `app/frontend/pages/auth/refused.tsx`
- `app/channels/application_cable/connection.rb`: cable identity from the session cookie.
- `config/routes.rb`: `resource :session, only: %i[new destroy]`, the Every callback, the dev login draw.
- `lib/tasks/users.rake`: `users:create` (pre-provisions an every.to person).
- `test/fixtures/users.yml`, `test/fixtures/files/every_oauth/*.json`, `test/support/every_oauth_helper.rb`,
  `test/models/user_test.rb`, `test/controllers/sessions_controller_test.rb`, `test/controllers/sessions/*`,
  `test/controllers/dev_login/*`, `test/lib/omniauth/strategies/every_test.rb`, `test/integration/authentication_gate_test.rb`,
  `test/tasks/users_rake_test.rb`, `test/test_helpers/session_test_helper.rb`

## Configuration

| Variable | Purpose |
|---|---|
| `EVERY_OAUTH_CLIENT_ID` | The OAuth client id Every provisions for happyhappy. |
| `EVERY_OAUTH_CLIENT_SECRET` | Its secret. |
| `EVERY_OAUTH_BASE_URL` | Every's OAuth origin, for example `https://every.to`. |
| `PUBLIC_BASE_URL` | happyhappy's public origin; the redirect URI is `<PUBLIC_BASE_URL>/auth/every/callback`. |

With any of the first three unset the app still boots, and the sign-in page
says Sign in with Every is not configured.

## Adopt into an existing app

1. Run `bin/rails generate authentication`, move `include Authentication` to the
   base `InertiaController`, and make public actions call
   `allow_unauthenticated_access`.
2. Add `omniauth` and `omniauth-oauth2`, copy `lib/omniauth/strategies/every.rb`
   and `config/initializers/omniauth.rb`, and add `omniauth` to the
   `config.autoload_lib` ignore list (the initializer requires the strategy).
3. Add `every_user_id` (unique, nullable), `name`, and `avatar_url` to `users`,
   copy `app/models/user/every_identity.rb`, and drop `has_secure_password`.
4. Copy `Sessions::EveryController`, the dev login controller and route file,
   and the two auth pages; route `GET /auth/every/callback` and
   `resource :session, only: %i[new destroy]`.
5. Ask Every for an OAuth client with the redirect URI
   `<PUBLIC_BASE_URL>/auth/every/callback` and set the variables below.

## Verify adoption

- `bin/rails test test/models/user_test.rb test/controllers/sessions_controller_test.rb test/controllers/sessions test/controllers/dev_login test/lib test/integration/authentication_gate_test.rb`
- An unauthenticated request to a gated Inertia page redirects to sign-in.
- In development, `bin/rails db:seed` then `/session/new` offers the dev login.

## Decisions & opt-ins

- **Only the legacy authorization-code mode is ported.** Baby Agent's OIDC and
  silent `prompt=none` modes, the workspace-deletion step-up, and its reauth
  context are not needed here.
- **Every every.to person has full access.** There are no roles in v1.
- **No open registration** is a deliberate default. The Every callback and
  `users:create` are the only writers.
