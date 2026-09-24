# Deploying

happyhappy deploys with [Kamal](https://kamal-deploy.org) 2.12+ to a Hetzner
server. `config/deploy.yml` is fully env-driven: every tenant-specific value is
read from the environment with **no default**, so a missing variable fails the
render loudly instead of silently reusing another app's config.

Two roles run from the same image on the same host:

| Role | Command | Containers | Notes |
|---|---|---|---|
| `web` | `./bin/thrust ./bin/rails server` | 1 | Behind kamal-proxy with SSL; runs Solid Queue inside Puma |
| `discord` | `bin/discord` | exactly 1 | Discord gateway bot; no proxy |

Both mount the same storage volume at `/rails/storage`, so they share the
SQLite databases. Never put the `discord` role on a second host: Discord
delivers every message to each connected session.

## 1. Hetzner host

Skip to step 2 if the app joins an existing Kamal host (for example the shared
box that already runs kamal-proxy for other apps); pick a new service name,
volume, and hostname so nothing collides.

1. In the Hetzner Cloud console, create a server: Ubuntu 24.04, a CX22 (x86,
   `KAMAL_BUILDER_ARCH=amd64`) or CAX11 (Arm, `KAMAL_BUILDER_ARCH=arm64`) is
   enough. Add your SSH public key when creating it and note the IPv4 address.
2. Attach a Hetzner firewall that allows inbound TCP 22 (SSH), 80, and 443 only.
   Port 80 must stay open for Let's Encrypt.
3. Create the deploy user and let it run Docker:

   ```sh
   ssh root@<server-ip>
   adduser --disabled-password --gecos "" ubuntu   # skip if the image already has it
   usermod -aG sudo ubuntu
   echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
   mkdir -p /home/ubuntu/.ssh && cp ~/.ssh/authorized_keys /home/ubuntu/.ssh/
   chown -R ubuntu:ubuntu /home/ubuntu/.ssh
   curl -fsSL https://get.docker.com | sh
   usermod -aG docker ubuntu
   ```

   Then `ssh ubuntu@<server-ip> docker ps` must work without a password.
4. Enable Hetzner backups for the server, or copy the storage volume off the
   host on a schedule. The SQLite databases live in the Docker volume named by
   `KAMAL_STORAGE_VOLUME` (`/var/lib/docker/volumes/<name>/_data`).

## 2. DNS

Create an `A` record for the app hostname (for example `happyhappy.every.to`)
pointing at the server's IPv4 address, plus an `AAAA` record if you use IPv6.
If the zone is on Cloudflare, set the record to DNS only (grey cloud) so
kamal-proxy can complete the Let's Encrypt HTTP challenge. The record must
resolve before `bin/kamal setup`, or the certificate request fails.

That hostname is `KAMAL_PROXY_HOST`, and `https://<hostname>` is
`PUBLIC_BASE_URL`. Every provider URL below is built from it.

## 3. Local deploy environment

1. Create `.kamal/deploy.env` (gitignored) with this app's values:

   ```sh
   # Required. The render fails loudly if any of these is unset.
   export KAMAL_SERVICE=happyhappy
   export KAMAL_IMAGE=kieranklaassen/happyhappy   # WITHOUT the registry host; registry.server (ghcr.io) is prepended
   export KAMAL_WEB_HOST=203.0.113.10             # the Hetzner server IPv4 (or an SSH alias)
   export KAMAL_PROXY_HOST=happyhappy.example.com
   export KAMAL_REGISTRY_USERNAME=kieranklaassen
   export KAMAL_STORAGE_VOLUME=happyhappy_storage
   export KAMAL_BUILDER_ARCH=amd64
   export KAMAL_SSH_USER=ubuntu
   export PUBLIC_BASE_URL=https://happyhappy.example.com
   export EVERY_OAUTH_BASE_URL=https://every.to

   # Optional, with defaults.
   # export APP_TIME_ZONE=Europe/Amsterdam              # default UTC; digest hours use it
   # export KAMAL_REGISTRY_SERVER=ghcr.io
   # export KAMAL_BUILDER_REMOTE=ssh://ubuntu@203.0.113.10   # build on the server, no cross-arch emulation
   # export RIFFREC_ENDPOINT=https://riffrec.example.com   # blank means capture off

   # Secrets. .kamal/secrets passes these through; they are never committed.
   # Prefer reading them from a password manager, for example
   #   export SLACK_BOT_TOKEN=$(op read op://happyhappy/slack/bot-token)
   export EVERY_OAUTH_CLIENT_ID=...
   export EVERY_OAUTH_CLIENT_SECRET=...
   export SLACK_SIGNING_SECRET=...
   export SLACK_BOT_TOKEN=...
   export DISCORD_BOT_TOKEN=...
   export INTERCOM_CLIENT_SECRET=...
   export POSTMARK_INBOUND_USER=...
   export POSTMARK_INBOUND_PASSWORD=...
   export X_BEARER_TOKEN=...
   export TYPESAFE_API_KEY=...
   ```

2. Ensure `config/master.key` exists locally (untracked, see `.gitignore`).
   A fresh clone CANNOT decrypt the template's `config/credentials.yml.enc`, so
   regenerate the pair for this app:

   ```sh
   rm config/credentials.yml.enc
   EDITOR=true bin/rails credentials:edit   # writes a new .enc + master.key
   ```

   Commit the new `credentials.yml.enc`; the key stays untracked.

3. Check the render before touching the server:

   ```sh
   source .kamal/deploy.env
   bin/kamal config     # prints both roles; fails loudly on a missing variable
   ```

### Secrets and settings reference

| Variable | Kind | Used by | Without it |
|---|---|---|---|
| `RAILS_MASTER_KEY` | secret | Rails | the app does not boot |
| `EVERY_OAUTH_CLIENT_ID`, `EVERY_OAUTH_CLIENT_SECRET` | secret | Sign in with Every | sign-in says it is not configured |
| `EVERY_OAUTH_BASE_URL` | clear, required | Sign in with Every | render fails |
| `PUBLIC_BASE_URL` | clear, required | OAuth redirect URI, Slack item links | render fails |
| `APP_TIME_ZONE` | clear, default `UTC` | digest hours and days, X month keys | UTC |
| `SLACK_SIGNING_SECRET` | secret | Slack events webhook | every Slack event gets 401 |
| `SLACK_BOT_TOKEN` | secret | Slack author lookups, escalations, digests | posts fail and keep the error |
| `DISCORD_BOT_TOKEN` | secret | `discord` role | the `discord` container exits and the deploy fails |
| `INTERCOM_CLIENT_SECRET` | secret | Intercom webhook | every Intercom webhook gets 401 |
| `POSTMARK_INBOUND_USER`, `POSTMARK_INBOUND_PASSWORD` | secret | Postmark inbound webhook | every Postmark request gets 401 |
| `X_BEARER_TOKEN` | secret | X polling | X sources record an error and never poll |
| `TYPESAFE_API_KEY` | secret | Jev classification | messages stay unclassified |

Secrets (`.kamal/secrets`) are resolved at deploy time via shell indirection:
`$(gh auth token)` for the registry, `$(cat config/master.key)` for the master
key, and `$VAR` from the environment for everything else. No raw credential is
ever committed.

## 4. Deploy

```sh
source .kamal/deploy.env
bin/kamal setup     # first time: installs kamal-proxy, boots web and discord
bin/kamal deploy    # subsequent deploys
```

`bin/discord` exits when `DISCORD_BOT_TOKEN` is empty, and Kamal then fails the
`discord` role. To ship web before the Discord bot exists, deploy with
`bin/kamal deploy --roles web`.

During a deploy the old and new `discord` containers can briefly both be
connected; Discord sources may show a gateway error until the new process
connects and clears it. Duplicate deliveries dedupe on the message id.

No user seeding is needed: any every.to account can sign in once Sign in with
Every is configured.

## 5. Provider setup

Replace `https://<host>` with `PUBLIC_BASE_URL`. Each provider connects one
Every account; sources in the app then pick channels, inboxes, addresses, and
queries inside it.

### Sign in with Every

- Register an OAuth client with Every (the Baby Agent flow, authorization code
  with scope `basic_profile`).
- Redirect URI: `https://<host>/auth/every/callback`
- Client id and secret: `EVERY_OAUTH_CLIENT_ID`, `EVERY_OAUTH_CLIENT_SECRET`.
  Every's base URL: `EVERY_OAUTH_BASE_URL`.
- Only verified `@every.to` addresses get in.

### Slack (community messages, escalations, digests)

- Create a Slack app in Every's workspace.
- Bot token scopes: `channels:history` (message events), `users:read` and
  `users:read.email` (author names and emails), `chat:write` (escalations and
  digests).
- Event Subscriptions: enable, Request URL `https://<host>/webhooks/slack/events`,
  subscribe to the bot event `message.channels`. Slack verifies the URL
  immediately, so deploy with `SLACK_SIGNING_SECRET` set first.
- Install the app; the Bot User OAuth Token is `SLACK_BOT_TOKEN`, and the
  Signing Secret (Basic Information) is `SLACK_SIGNING_SECRET`.
- Invite the bot to every public channel a Slack source selects and to each
  product's support channel (escalations and digests post there).

### Discord

- Create an application and bot in the Discord Developer Portal. The bot token
  is `DISCORD_BOT_TOKEN`.
- Under Bot, enable the **Message Content** privileged intent; without it every
  message arrives empty.
- Invite the bot to each server with the `bot` scope and the View Channels and
  Read Message History permissions. Sources select channel ids.
- No webhook URL: the `discord` role holds the gateway connection.

### Intercom

- In the Intercom Developer Hub, create an app for Every's workspace. Its client
  secret (Basic information) is `INTERCOM_CLIENT_SECRET`; it signs each
  notification's `X-Hub-Signature`.
- Webhooks: endpoint URL `https://<host>/webhooks/intercom`, topics
  `conversation.user.created` and `conversation.user.replied`. Intercom checks
  the URL with a HEAD request when saved.
- Sources select a team or inbox id; a source with selector `*` catches
  conversations no other source matches.

### Email (Postmark inbound)

- In Postmark, open the server's inbound message stream. Choose a user and a long
  random password for `POSTMARK_INBOUND_USER` and `POSTMARK_INBOUND_PASSWORD`.
- Inbound webhook URL, with the credentials embedded as basic auth:
  `https://<user>:<password>@<host>/webhooks/postmark`
- Forward each support address (for example `help@cora.computer`) to the
  stream's inbound address, or point an inbound domain's MX record at Postmark.
  Email sources select the support address the mail was sent to.

### X

- In the X developer console, create a project and app; the app-only bearer
  token is `X_BEARER_TOKEN`.
- **Set a monthly spending limit in the X developer console.** Each X source
  also has an in-app monthly limit that pauses polling before it would pass the
  limit, but that limit is an estimate from post and user counts because X does
  not report cost. The console limit is the backstop if the estimate is off.
- No webhook URL: X sources are searched every 15 minutes.

### TypeSafe (Jev)

- Create an API key in TypeSafe; it is `TYPESAFE_API_KEY`.

## Smoke check after deploy

- `https://<host>/up` returns 200.
- Sign in with an every.to account.
- `bin/kamal app logs --roles discord` shows `[discord] starting gateway bot`.
- Post in a Slack source channel, reply in a Discord source channel, and send a
  test mail; each shows up in the feed and gets classified.

## Caveat: git worktrees do not inherit your shell secrets

`.kamal/deploy.env` is per-checkout and gitignored. A **git worktree** created
for isolated work starts without it, and `config/master.key` is not copied into a
fresh worktree either. Before deploying from a worktree, re-create
`.kamal/deploy.env` and copy `config/master.key` into it; otherwise the render
fails loudly (which is the intended safety behavior, not a bug).
