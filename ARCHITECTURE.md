# Architecture

Imision is a plain Mix library (OTP app `:imision`) that runs inside a host Phoenix app. This doc describes what is built; the full design, stories and open decisions are in [`docs/PROJECT.md`](docs/PROJECT.md).

## What exists

The `mix new` skeleton (`lib/imision.ex` and its test) and `Imision.Migration` (`lib/imision/migration.ex`): `up/1` and `down/1` are no-ops until version 1 arrives (INS-02), so they change nothing.

Imision's own tests run against Postgres. `test/support/` (compiled only in `:test`) holds `Imision.Test.Repo`, configured in `config/test.exs` with the SQL sandbox; `Imision.DataCase`, which checks out a sandbox connection per test; and a wrapper migration in `test/support/postgres/migrations/` that calls `Imision.Migration`, as a host app's migration does. `mix test` creates and migrates the `imision_test` database.

The dashboard stylesheet and its bundled fonts are in `priv/static/`, with mockups in `docs/design/`. Tooling is in place: Styler (`.formatter.exs`), Credo with ExSlop (`.credo.exs`).

`.gitignore` excludes `dev/`, where each maintainer keeps a local Phoenix host app for development; it is not in the repo (see the README).

## Stack

Elixir 1.20. Runtime dependencies: `ecto_sql`, `postgrex`. Planned: `phoenix_live_view`, `jason`, `telemetry`; optional `swoosh`, `oban`, `igniter`. Imision has no endpoint, router or repo of its own; the host app supplies them.

## Where new code goes

| Path | Holds |
|---|---|
| `lib/imision.ex` | The `Imision` supervisor, config validation, `report/3` |
| `lib/imision/migration.ex` | Versioned `up/down` for the `imision_` tables |
| `lib/imision/capture/` | `:logger` handler, Phoenix and Oban telemetry handlers, capture worker |
| `lib/imision/errors/` | Schemas, fingerprint, upsert, pruner |
| `lib/imision/notifications/` | Notifier, `Channel` behaviour, channels (Email first) |
| `lib/imision/web/router.ex` | The `imision_dashboard` router macro |
| `lib/imision/web/live/` | Error list, error detail, notifications, login LiveViews |
| `lib/mix/tasks/imision.install.ex` | Igniter installer |
| `priv/static/` | `app.css` (exists) and a prebuilt `app.js`, committed; `fonts/` holds the bundled WOFF2 files and their OFL licenses |
| `docs/design/` | Static HTML mockups of the dashboard screens, styled by `priv/static/app.css`: the reference for LiveView markup and class names |
| `dev/` | Small Phoenix host app for development: local and gitignored, its own Mix project with a path dependency on Imision; not in the repo or the Hex package |
| `test/imision/…` | Tests mirroring `lib/imision/…` |
| `test/support/` | Test-only modules: `Imision.Test.Repo` (`repo.ex`), `Imision.DataCase` (`data_case.ex`) |
| `test/support/postgres/migrations/` | Wrapper migrations for the test repo that call `Imision.Migration`, as a host app does; each released version gets its own |

## Data

All tables are owned by Imision, live in the host's database and are prefixed `imision_`: `errors`, `occurrences`, `hourly_counts`, `channels`, `rules`, `deliveries`. None exist yet: `Imision.Migration` has no versions, so the test database holds only `schema_migrations`.

## Decisions

- [0001](docs/adr/0001-embedded-library-in-host-app.md): embedded library using the host's repo, not a separate service
- [0002](docs/adr/0002-database-coordinates-nodes.md): the database, not the cluster, coordinates nodes
- [0003](docs/adr/0003-fingerprint-ignores-message.md): fingerprint ignores the message
- [0004](docs/adr/0004-built-in-dashboard-login.md): built-in dashboard login (proposed)
- [0005](docs/adr/0005-no-hard-oban-dependency.md): no hard Oban dependency (proposed)
