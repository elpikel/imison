# Architecture

Imison is a plain Mix library (OTP app `:imison`) that runs inside a host Phoenix app. This doc describes what is built; the full design, stories and open decisions are in [`docs/PROJECT.md`](docs/PROJECT.md).

## What exists

The `Imison` supervisor (`lib/imison.ex`), which a host starts with `{Imison, opts}` in its supervision tree; `child_spec/1` uses the `name` option (default `Imison`) as the id. `start_link/1` builds an `Imison.Config` struct (`lib/imison/config.ex`) holding every documented option with its default; `Config.new/1` raises `ArgumentError` on a missing, unknown, duplicate or wrongly typed option, so a bad config fails the host's boot. Type checks are in `Imison.Validation` (`lib/imison/validation.ex`, internal), modelled on `Oban.Validation`. The supervisor registers in `Imison.Registry` (`lib/imison/registry.ex`, a unique-key `Registry` started by `Imison.Application`) with the config as its value; `Imison.config/1` reads it back by name. The supervisor's children are the capture worker and, after it, the capture handlers; with `enabled: false` (default `true`) it starts neither, so no handler is attached and `Imison.Capture.capture/2` finds no worker and does nothing, while the supervisor still runs and registers its config.

Versioned migrations, modelled on Oban's. `Imison.Migration` (`lib/imison/migration.ex`) is the public module and a behaviour (`up/1`, `down/1`, `migrated_version/1`); it dispatches on the repo's adapter to `Imison.Migrations.Postgres` (`lib/imison/migrations/postgres.ex`), the only implementation. That module records the applied version as a comment on `imison_errors`, so `up/1` applies only missing versions (default: the latest) and `down/1` rolls back down to and including the given one. Each version is its own module: `Imison.Migrations.Postgres.V01` creates the six tables. The `prefix:` option puts them in another Postgres schema; the `prefix` config option (default `"public"`) names that schema for Imison's queries.

Error grouping. `Imison.Errors.record/2` (`lib/imison/errors.ex`, internal) takes the config and one occurrence (kind, message, stack trace, context, release, `occurred_at`) and writes it in one `repo.transact`: it upserts the error on `fingerprint`, incrementing `occurrence_count` in SQL, moving `last_seen_at` only forward and taking the message of the newest occurrence; inserts the occurrence; and upserts the hourly count. Every write uses the configured `prefix`. The capture worker calls it, for handler captures and `report/3` alike. `Imison.Errors.Frame` reads the stack trace once into frames; argument values are never stored, only their arity. `Imison.Errors.Fingerprint` hashes (SHA-256) the kind with the first application frame's module, function and arity; application frames are modules of the host repo's `otp_app`, and with none it falls back to the first frame. That frame is also the error's location, `Mod.fun/arity (file:line)`. The Ecto schemas `Imison.Errors.Error`, `Occurrence` and `HourlyCount` map the V01 tables.

Asynchronous capture. `Imison.Capture` (`lib/imison/capture.ex`, internal) is what capture handlers call: `capture/2` takes the instance name and an event (the map `Errors.record/2` takes, without `release`) and runs in the caller. It looks the worker up with `Imison.Registry.lookup/2`, which returns `nil` when nothing is registered or the registry itself isn't running; with no instance under that name it does nothing, with the worker's mailbox at or above its queue limit it drops the event and increments a `:counters` counter, otherwise it casts the event. It always returns `:ok` and never blocks on the worker. `dropped/1` reads the counter (0 when no instance runs under the name). `Imison.Capture.Worker` (`lib/imison/capture/worker.ex`, internal) is a GenServer started by the `Imison` supervisor; it registers with `Imison.Registry.via/3` under the `Imison.Capture.Worker` role, with `%{dropped: counter, queue_limit: limit}` as its Registry value. The queue limit is a start option (default 1 000), not a config option. The worker filters the event's context, makes it JSON-safe, sets the context's `runtime` to `%{"node" => Atom.to_string(node())}` (the node that caught the error; set last, so a caller's own `runtime` key is replaced), adds the configured `release` and calls `Errors.record/2`; anything raised, thrown or exited is logged by `Imison.Capture.FailureLog` under `domain: [:imison]` (so the logger handler skips Imison's own failures) and the worker carries on with the next event. Before recording, the worker drops events whose kind is a module listed in the `ignore` option.

Capture handlers. `Imison.Capture.event/2` builds an event from a failure (`%{kind: :error | :exit | :throw, reason: _, stacktrace: _}`, the shape Phoenix and Oban telemetry metadata already has) and a context map: `:error` reasons are normalized to an exception, whose module (`inspect`ed) is the kind and `Exception.message/1` the message; throws get kind `"throw"` and the `inspect`ed value; exits get kind `"exit"` and `Exception.format_exit/1`. The context is passed through as built; `occurred_at` is `DateTime.utc_now()`. `Imison.report/3` reuses it. `Imison.Capture.Handlers` (`lib/imison/capture/handlers.ex`, internal) is a GenServer child of the `Imison` supervisor, after the worker; it traps exits, attaches both handlers in `init` (detaching any left attached by a predecessor killed without `terminate` first) and detaches them in `terminate`, so stopping an instance removes its handlers. `Imison.Capture.LoggerHandler` (`lib/imison/capture/logger_handler.ex`) is an Erlang `:logger` handler, one per instance (its id is an atom built from a hash of the instance name, so any name fits; its config holds the name). It acts only on log events whose metadata has `crash_reason` (set by Elixir's logger translator for crashed GenServers, Tasks and spawned processes): `{exception, stacktrace}` → `:error`, `{{:nocatch, value}, stacktrace}` → `:throw`, anything else → `:exit` (the translator has already turned Erlang errors such as `:badarith` into exceptions, so only real exit reasons get here). It skips events whose `domain` contains `:imison` (Imison's own logs), `:cowboy` or `:bandit` (request crashes the Phoenix handler already reports). The context is `metadata` with the crashed process's `pid` and `registered_name`. `Imison.Capture.Telemetry` (`lib/imison/capture/telemetry.ex`) attaches one telemetry handler per instance (id `{Imison.Capture.Telemetry, name}`, a named function, not a closure) to `[:phoenix, :router_dispatch, :exception]` (context `request`: method, path, params, headers from `conn`; a `Plug.Conn.WrapperError` reason is unwrapped to the failure it wraps) and `[:oban, :job, :exception]` (context `metadata.job`: worker, queue, args, attempt). Both are attached unconditionally and reference no Phoenix, Plug or Oban module, so a host without them is unaffected. Handlers run in the crashing process; each wraps its work in `try/catch` (a raising logger or telemetry handler is removed) and logs its own failures through `Imison.Capture.FailureLog`.

Filtering. `Imison.Capture.Filter` (`lib/imison/capture/filter.ex`, internal) walks the context (maps, struct fields, keyword and other lists, tuples, at any depth) and replaces the value of every atom or string key whose downcased name contains one of the `filter` option's words (downcased) with `"[FILTERED]"`, as Phoenix's `filter_parameters` matches: with the default words `password_confirmation` and `X-Api-Token` are filtered. A custom `filter` replaces the default list. The worker filters first, then converts what JSON can't encode (structs, tuples, pids, invalid UTF-8, improper lists are `inspect`ed, map keys become strings), so a filtered value is never `inspect`ed and the jsonb insert can't fail; every capture path (logger, Phoenix, Oban, `report/3`) goes through it. The request context holds no query string: its values are already in `params`, where they are filtered.

Reporting rescued exceptions. `Imison.report/3` (`lib/imison.ex`, public) is the manual capture path: it builds the event with `Imison.Capture.event/2` from `%{kind: :error, reason: exception, stacktrace: stacktrace}` (so a non-exception value, such as an Erlang error term, is normalized by `Exception.normalize/3` like any `:error` reason) and the context `%{metadata: metadata}` (a keyword list is converted to a map), then calls `Imison.Capture.capture/2` with the name `Imison`. It reports only to the default instance; instances with a custom `name` can't be reached from it yet. It runs in the caller, always returns `:ok` and wraps its work in `try/catch`, logging its own failures (such as metadata that is neither a map nor a keyword list) through `Imison.Capture.FailureLog`; `ignore`, filtering and the JSON-safe conversion happen in the worker, as for captured crashes.

Failure logs. `Imison.Capture.FailureLog.error/2` (`lib/imison/capture/failure_log.ex`, internal) logs a failure inside Imison (handlers and worker) with `Logger.error` under `domain: [:imison]`: the stack trace's argument lists are reduced to arities and a `FunctionClauseError` banner leaves out its arguments, so a failing handler never prints a conn, its cookies or an event into the host's logs.

Imison's own tests run against Postgres. `test/support/` (compiled only in `:test`) holds `Imison.Test.Repo`, configured in `config/test.exs` with the SQL sandbox; `Imison.DataCase`, which checks out a sandbox connection per test; and a wrapper migration in `test/support/postgres/migrations/` that calls `Imison.Migration`, as a host app's migration does. `mix test` creates and migrates the `imison_test` database.

The dashboard stylesheet and its bundled fonts are in `priv/static/`, with mockups in `docs/design/`. Tooling is in place: Styler (`.formatter.exs`, which also imports the `ecto` and `ecto_sql` formatter config), Credo with ExSlop (`.credo.exs`).

`.gitignore` excludes `dev/`, where each maintainer keeps a local Phoenix host app for development; it is not in the repo (see the README).

## Stack

Elixir 1.20. Runtime dependencies: `ecto_sql`, `postgrex`, `telemetry`. Test only: `plug` (tests emit the Phoenix event with a real `%Plug.Conn{}`). Planned: `phoenix_live_view`, `jason`; optional `swoosh`, `igniter`. Oban is never a dependency: its job-failure event is handled by telemetry alone. Imison has no endpoint, router or repo of its own; the host app supplies them.

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
| `lib/imison/capture.ex` | `capture/2` (cast or drop, in the caller), `event/2` (failure and context → event) and `dropped/1` |
| `lib/imison/capture/` | Capture worker (`worker.ex`), context filter (`filter.ex`), Imison's own failure logging (`failure_log.ex`), the handlers' lifecycle process (`handlers.ex`), the `:logger` handler (`logger_handler.ex`) and the Phoenix and Oban telemetry handlers (`telemetry.ex`) |
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

- `imison_errors`: one row per fingerprint (unique index on `fingerprint`), with status, mute flag, first and last seen, occurrence count and `regressed_at` (nullable: when a resolved error last came back; set in the same `ON CONFLICT` update that flips `resolved` to `unresolved`)
- `imison_occurrences`: stack trace and context (jsonb: `request`, `metadata`, and `runtime.node`, the node that captured it), release, time; `error_id` cascades on delete; indexed on `(error_id, occurred_at)`
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
