# Residual review findings: U23 stack upgrade to compound-stack-rails 0.8.0

Source run: lfg pipeline for U23 (branch `cursor/happyhappy-u23-stack-upgrade-5b96`), plan
`docs/plans/2026-09-24-001-feat-happyhappy-sentiment-feed-plan.md`. Simplify and code review ran
inline because no subagents were available, so the review lenses are not independent of each other
and no cross-model peer ran. Docker is not installed in the build environment, so the production
image was not built; the build check used the fallback below. No tracker sink was used; this file is
the durable record.

## Checked in review

- Each 0.7.0 entry landed in its own commit, and its Verify section passed before the next began.
- The Geneva Drive installer ran with `--skip`: the initializer and the locally patched nullable-hero
  migration are untouched, and the three new migrations match upstream except the rubocop spacing
  the entry asks for. On a seeded SQLite copy, row counts, the cascade foreign key,
  `PRAGMA integrity_check`, and `PRAGMA foreign_key_check` are unchanged after migrating.
- `.template-manifest.yml`, `CHANGELOG.md`, `docs/changelog/`, `.github/workflows/ci.yml`, and
  `.github/dependabot.yml` match upstream; webmcp module files match upstream except the planned
  `ApplicationTool` and `ToolRegistry` adaptations from U21.
- `package-lock.json` keeps the `happyhappy` name after the npm refresh.
- Build fallback: `ruby:4.0.7-slim` exists on Docker Hub for amd64 and arm64, node-build has
  24.21.0, and in a scratch copy on Ruby 4.0.7 a deployment-mode `bundle install`, bootsnap
  precompile, `assets:precompile`, `db:prepare`, and a production Puma serving `/up` and the
  sign-in page with 200 all succeeded. `bin/kamal config` renders with dummy values.

## Residual Review Findings

- P3 `db/migrate/20260925045000_add_metadata_to_geneva_drive_workflows.rb` and
  `db/migrate/20260925045002_add_resumable_step_support_to_geneva_drive_step_executions.rb`
  (upstream): both are `change` migrations guarded by `column_exists?`, so rolling them back is a
  no-op and the nullable columns stay. Harmless, but a rollback does not restore the 0.5 schema.
  Fix upstream in Geneva Drive rather than editing generated files.
- P3 production image: not built here (no Docker). The first real build on the deploy builder pulls
  the new `ruby:4.0.7-slim` (Debian trixie) base and compiles native gems on Ruby 4; watch that
  build and the `/up` health check on the first deploy.
- P3 `vite build`: `@inertiajs/vite` 3.7.1 logs a `SOURCEMAP_BROKEN` warning during
  `assets:precompile`. Cosmetic; the build succeeds.
