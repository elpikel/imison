# Architecture

Imison is a plain Mix library (OTP app `:imison`) that runs inside a host Phoenix app. This doc describes what is built; the full design, stories and open decisions are in [`docs/PROJECT.md`](docs/PROJECT.md).

## What exists

The `Imison` supervisor (`lib/imison.ex`), which a host starts with `{Imison, opts}` in its supervision tree; `child_spec/1` uses the `name` option (default `Imison`) as the id. `start_link/1` builds an `Imison.Config` struct (`lib/imison/config.ex`) holding every documented option with its default; `Config.new/1` raises `ArgumentError` on a missing, unknown, duplicate or wrongly typed option, so a bad config fails the host's boot. Type checks are in `Imison.Validation` (`lib/imison/validation.ex`, internal), modelled on `Oban.Validation`. The supervisor registers in `Imison.Registry` (`lib/imison/registry.ex`, a unique-key `Registry` started by `Imison.Application`) with the config as its value; `Imison.config/1` reads it back by name. The supervisor's only child so far is the capture worker.

Versioned migrations, modelled on Oban's. `Imison.Migration` (`lib/imison/migration.ex`) is the public module and a behaviour (`up/1`, `down/1`, `migrated_version/1`); it dispatches on the repo's adapter to `Imison.Migrations.Postgres` (`lib/imison/migrations/postgres.ex`), the only implementation. That module records the applied version as a comment on `imison_errors`, so `up/1` applies only missing versions (default: the latest) and `down/1` rolls back down to and including the given one. Each version is its own module: `Imison.Migrations.Postgres.V01` creates the six tables. The `prefix:` option puts them in another Postgres schema; the `prefix` config option (default `"public"`) names that schema for Imison's queries.

Error grouping. `Imison.Errors.record/2` (`lib/imison/errors.ex`, internal) takes the config and one occurrence (kind, message, stack trace, context, release, `occurred_at`) and writes it in one `repo.transact`: it upserts the error on `fingerprint`, incrementing `occurrence_count` in SQL, moving `last_seen_at` only forward and taking the message of the newest occurrence; inserts the occurrence; and upserts the hourly count. Every write uses the configured `prefix`. The capture worker calls it; `report/3` will. `Imison.Errors.Frame` reads the stack trace once into frames; argument values are never stored, only their arity. `Imison.Errors.Fingerprint` hashes (SHA-256) the kind with the first application frame's module, function and arity; application frames are modules of the host repo's `otp_app`, and with none it falls back to the first frame. That frame is also the error's location, `Mod.fun/arity (file:line)`. The Ecto schemas `Imison.Errors.Error`, `Occurrence` and `HourlyCount` map the V01 tables.

Asynchronous capture. `Imison.Capture` (`lib/imison/capture.ex`, internal) is what capture handlers will call: `capture/2` takes the instance name and an event (the map `Errors.record/2` takes, without `release`) and runs in the caller. It looks the worker up with `Imison.Registry.lookup/2`, which returns `nil` when nothing is registered or the registry itself isn't running; with no instance under that name it does nothing, with the worker's mailbox at or above its queue limit it drops the event and increments a `:counters` counter, otherwise it casts the event. It always returns `:ok` and never blocks on the worker. `dropped/1` reads the counter (0 when no instance runs under the name). `Imison.Capture.Worker` (`lib/imison/capture/worker.ex`, internal) is a GenServer started by the `Imison` supervisor; it registers with `Imison.Registry.via/3` under the `Imison.Capture.Worker` role, with `%{dropped: counter, queue_limit: limit}` as its Registry value. The queue limit is a start option (default 1 000), not a config option. The worker adds the configured `release` and calls `Errors.record/2`; anything raised, thrown or exited is logged with `Logger.error` under `domain: [:imison]` (so the future logger handler can skip Imison's own failures) and the worker carries on with the next event.

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
| `lib/imison/capture.ex` | `capture/2` (cast or drop, in the caller) and `dropped/1` |
| `lib/imison/capture/` | Capture worker (`worker.ex`); later the `:logger` handler and Phoenix and Oban telemetry handlers |
| `lib/imison/errors.ex` | `record/2`: one occurrence grouped into its error, in one transaction |
| `lib/imison/errors/` | `Error`, `Occurrence` and `HourlyCount` schemas, `Frame`, `Fingerprint`; pruner later |
| `lib/imison/notifications/` | Notifier, `Channel` behaviour, channels (Email first) |
| `lib/imison/web/router.ex` | The `imison_dashboard` router macro |
| `lib/imison/web/live/` | Error list, error detail, notifications, login LiveViews |
| `lib/mix/tasks/imison.install.ex` | Igniter installer |
| `priv/static/` | `app.css` (exists) and a prebuilt `app.js`, committed; `fonts/` holds the bundled WOFF2 files and their OFL licenses |
| `docs/design/` | Static HTML mockups of the dashboard screens, styled by `priv/static/app.css`: the reference for LiveView markup and class names |
| `dev/` | Small Phoenix host app for development: local and gitignored, its own Mix project with a path dependency on Imison; not in the repo or the Hex package |
| `test/imison/…` | Tests mirroring `lib/imison/…` |
| `test/support/` | Test-only modules: `Imison.Test.Repo` (`repo.ex`), `Imison.DataCase` (`data_case.ex`), `Imison.Test.PrivatePrefix` (`private_prefix.ex`): Imison installed under a private `prefix` inside the test's sandbox |
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
