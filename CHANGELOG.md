# Changelog

Human-readable index of the agent-executable entries under
[`docs/changelog/`](docs/changelog/README.md). Each entry is written as upgrade
instructions an agent applies to a downstream app — see the README there for the
filter+apply algorithm.

## 0.6.0

- **0.6.0-001** · _feat_ · feature_flags — [Add feature flags module](docs/changelog/0.6.0-001-add-feature-flags-module.md).
  Registers Flipper as the house feature-flag choice, documentation-first:
  per-user actors, a YAML registry that production creates disabled, an
  admin-only dashboard, a client reader, the rollout ladder, the cleanup
  migration, and test conventions, all as Cora runs them.

## 0.5.1

- **0.5.1-001** · _fix_ · frontend — [Inertia asset-version chdir race](docs/changelog/0.5.1-001-inertia-version-chdir-race.md).
  `ViteRuby.digest` runs inside a process-wide `Dir.chdir` block, so concurrent
  Inertia requests raised "conflicting chdir during another chdir block" and 500'd.
  Mutex-guarded, and memoized outside development/test.

## 0.5.0

- **0.5.0-001** · _feat_ · pwa — [Add PWA module](docs/changelog/0.5.0-001-add-pwa-module.md).
  Installable out of the box via Rails' built-in PwaController: config-driven
  manifest and layout identity, Inertia-safe service worker (navigate-only,
  rejection-only offline fallback), static offline page, client registration.

## 0.4.0

- **0.4.0-001** · _feat_ · geneva_drive — [Add Geneva Drive workflow module](docs/changelog/0.4.0-001-add-geneva-drive-module.md).
  Released 0.5.0 engine, generated persistence, Solid Queue housekeeping,
  SQLite history-preservation guard, runtime compatibility proof, and an
  independently adoptable module boundary.

## 0.3.0

- **0.3.0-001** · _feat_ · copse — [Add copse dev-environment module](docs/changelog/0.3.0-001-add-copse-module.md).
  Deterministic per-app/per-worktree dev hostnames, ports, and databases; copse
  launcher as bin/dev with web first in Procfile.dev.

## 0.2.3

- **0.2.3-001** · _fix_ · deploy, frontend — [Deploy hardening from the first tenant](docs/changelog/0.2.3-001-deploy-hardening-from-first-tenant.md).
  Dockerfile ships .ruby-version + Node for the Vite build; optional remote
  builder; KAMAL_IMAGE and fresh-clone credentials documented.

## 0.2.2

- **0.2.2-001** · _feat_ · frontend — [Cloudflare tunnel previews](docs/changelog/0.2.2-001-cloudflared-tunnel-previews.md).
  Adds `bin/tunnel` (cloudflared quick tunnel over Rails-served built assets) and
  allows `*.trycloudflare.com` in development host authorization.

## 0.2.1

- **0.2.1-001** · _fix_ · auth, deploy — [Enforce production SSL](docs/changelog/0.2.1-001-enforce-production-ssl.md).
  Re-enables assume_ssl/force_ssl so session cookies ship Secure with HSTS.
- **0.2.1-002** · _fix_ · riffrec — [Rename capture key to RIFFREC_PUBLIC_KEY](docs/changelog/0.2.1-002-riffrec-public-key-rename.md).
  Browser-shipped key moves from env.secret to env.clear; no secret-shaped naming.
- **0.2.1-003** · _fix_ · auth, agent-conventions — [Sign-in submit test + AGENTS.md module list](docs/changelog/0.2.1-003-signin-submit-test-and-agents-module-list.md).

## 0.2.0

- **0.2.0-001** · _feat_ · ruby_native — [Add Ruby Native module](docs/changelog/0.2.0-001-add-ruby-native-module.md).
  Registers rubynative.com as a house module for native iOS/Android distribution;
  documentation-first, no gem or license in the template.

## 0.1.0

- **0.1.0-001** · _feat_ · all modules — [Initial template](docs/changelog/0.1.0-001-initial-template.md).
  Establishes the born-complete baseline: Rails 8.1 + Inertia/React + Kamal + the
  house modules (frontend, auth, jobs, testing, ci, deploy, ruby_llm,
  serialization, riffrec, agent-conventions).
