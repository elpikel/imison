# Architecture

Imison is a plain Mix library (OTP app `:imison`) that runs inside a host Phoenix app. This doc describes what is built; the full design, stories and open decisions are in [`docs/PROJECT.md`](docs/PROJECT.md).

## What exists

The `Imison` supervisor (`lib/imison.ex`), which a host starts with `{Imison, opts}` in its supervision tree; `child_spec/1` uses the `name` option (default `Imison`) as the id. `start_link/1` builds an `Imison.Config` struct (`lib/imison/config.ex`) holding every documented option with its default; `Config.new/1` raises `ArgumentError` on a missing, unknown, duplicate or wrongly typed option, so a bad config fails the host's boot. Type checks are in `Imison.Validation` (`lib/imison/validation.ex`, internal), modelled on `Oban.Validation`. The supervisor registers in `Imison.Registry` (`lib/imison/registry.ex`, a unique-key `Registry` started by `Imison.Application`) with the config as its value; `Imison.config/1` reads it back by name. The supervisor has no children yet.

Versioned migrations, modelled on Oban's. `Imison.Migration` (`lib/imison/migration.ex`) is the public module and a behaviour (`up/1`, `down/1`, `migrated_version/1`); it dispatches on the repo's adapter to `Imison.Migrations.Postgres` (`lib/imison/migrations/postgres.ex`), the only implementation. That module records the applied version as a comment on `imison_errors`, so `up/1` applies only missing versions (default: the latest) and `down/1` rolls back down to and including the given one. Each version is its own module: `Imison.Migrations.Postgres.V01` creates the six tables. The `prefix:` option puts them in another Postgres schema; the `prefix` config option (default `"public"`) names that schema for Imison's queries.

Imison's own tests run against Postgres. `test/support/` (compiled only in `:test`) holds `Imison.Test.Repo`, configured in `config/test.exs` with the SQL sandbox; `Imison.DataCase`, which checks out a sandbox connection per test; and a wrapper migration in `test/support/postgres/migrations/` that calls `Imison.Migration`, as a host app's migration does. `mix test` creates and migrates the `imison_test` database.

The dashboard stylesheet and its bundled fonts are in `priv/static/`, with mockups in `docs/design/`. Tooling is in place: Styler (`.formatter.exs`, which also imports the `ecto` and `ecto_sql` formatter config), Credo with ExSlop (`.credo.exs`).

`.gitignore` excludes `dev/`, where each maintainer keeps a local Phoenix host app for development; it is not in the repo (see the README).

## Stack

Elixir 1.20. Runtime dependencies: `ecto_sql`, `postgrex`. Planned: `phoenix_live_view`, `jason`, `telemetry`; optional `swoosh`, `oban`, `igniter`. Imison has no endpoint, router or repo of its own; the host app supplies them.

## Where new code goes

| Path | Holds |
|---|---|
| `lib/imison.ex` | The `Imison` supervisor, `config/1`, `report/3` |
| `lib/imison/application.ex` | Imison's OTP application: starts `Imison.Registry` |
| `lib/imison/config.ex` | `%Imison.Config{}`: every option with its default, `new/1` and `validate/1` |
| `lib/imison/validation.ex` | Internal option-schema checks behind `Config.validate/1` |
| `lib/imison/registry.ex` | Registry of Imison instances and their processes; holds each instance's config |
| `lib/imison/migration.ex` | Versioned `up/down` for the `imison_` tables |
| `lib/imison/migrations/postgres.ex` | Postgres migrator: version tracking and the `prefix` option |
| `lib/imison/migrations/postgres/vNN.ex` | One module per migration version (`V01`, `V02`, …) |
| `lib/imison/capture/` | `:logger` handler, Phoenix and Oban telemetry handlers, capture worker |
| `lib/imison/errors/` | Schemas, fingerprint, upsert, pruner |
| `lib/imison/notifications/` | Notifier, `Channel` behaviour, channels (Email first) |
| `lib/imison/web/router.ex` | The `imison_dashboard` router macro |
| `lib/imison/web/live/` | Error list, error detail, notifications, login LiveViews |
| `lib/mix/tasks/imison.install.ex` | Igniter installer |
| `priv/static/` | `app.css` (exists) and a prebuilt `app.js`, committed; `fonts/` holds the bundled WOFF2 files and their OFL licenses |
| `docs/design/` | Static HTML mockups of the dashboard screens, styled by `priv/static/app.css`: the reference for LiveView markup and class names |
| `dev/` | Small Phoenix host app for development: local and gitignored, its own Mix project with a path dependency on Imison; not in the repo or the Hex package |
| `test/imison/…` | Tests mirroring `lib/imison/…` |
| `test/support/` | Test-only modules: `Imison.Test.Repo` (`repo.ex`), `Imison.DataCase` (`data_case.ex`) |
| `test/support/postgres/migrations/` | Wrapper migrations for the test repo that call `Imison.Migration`, as a host app does; each released version gets its own |

## Data

All tables are owned by Imison, live in the host's database (schema `public` unless `prefix` says otherwise) and are prefixed `imison_`. Version 1 creates them; ids are `bigserial`, timestamps `utc_datetime_usec` (except `imison_hourly_counts.hour`, `utc_datetime`), status-like values text.

- `imison_errors`: one row per fingerprint (unique index on `fingerprint`), with status, mute flag, first and last seen, occurrence count
- `imison_occurrences`: stack trace and context (jsonb), release, time; `error_id` cascades on delete; indexed on `(error_id, occurred_at)`
- `imison_hourly_counts`: count per error per hour; unique `(error_id, hour)`; `error_id` cascades on delete
- `imison_channels`: notification channel type, enabled flag, config (jsonb)
- `imison_rules`: notification trigger and enabled flag
- `imison_deliveries`: sent notifications; `channel_id` and `error_id` (nullable, digests have none) cascade on delete and are indexed

## Decisions

- [0001](docs/adr/0001-embedded-library-in-host-app.md): embedded library using the host's repo, not a separate service
- [0002](docs/adr/0002-database-coordinates-nodes.md): the database, not the cluster, coordinates nodes
- [0003](docs/adr/0003-fingerprint-ignores-message.md): fingerprint ignores the message
- [0004](docs/adr/0004-built-in-dashboard-login.md): built-in dashboard login (proposed)
- [0005](docs/adr/0005-no-hard-oban-dependency.md): no hard Oban dependency (proposed)
