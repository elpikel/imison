# Imison

An error tracker you add to a Phoenix app as a library, installed the way Oban is: one dependency, one install task, one migration. It captures errors inside the host app, groups them, stores them in the app's own Postgres and serves a dashboard from the app's router.

**Status:** design stage. The `Imison` supervisor with validated config (read back with `Imison.config/1`), versioned migrations creating the six `imison_` tables (version 1), error grouping and capture without code changes exist: crashed processes, Phoenix request exceptions and Oban job failures are recorded in the background, as are exceptions the app rescues and reports with `Imison.report/3`, except exceptions listed in `ignore`; `enabled: false` switches capture off. The dashboard mounts in the host's router with `imison_dashboard` and serves its own assets, but shows only an empty error list so far; see [`docs/PROJECT.md`](docs/PROJECT.md) for the design and user stories.

## Stack

Elixir 1.20, plain Mix library. Dependencies: `ecto_sql` and `postgrex` (Imison uses the host's repo), `telemetry` (Phoenix and Oban capture) and `phoenix_live_view` (the dashboard; brings `phoenix` and `phoenix_html`), required as with Oban Web. Planned: optional Swoosh (email) and Igniter (installer). Oban is not a dependency: Imison handles its job-failure telemetry event when the host runs Oban.

## Installation (planned)

```elixir
# mix.exs of the host app
{:imison, "~> 0.1"},
{:igniter, "~> 0.5", only: [:dev]}
```

```sh
mix deps.get
mix imison.install
mix ecto.migrate
```

The installer, the manual steps and every option are in [`docs/PROJECT.md`](docs/PROJECT.md#installation).

## Configuration

Built today: add Imison to the host's supervision tree, after its repo, and set its options in `config/runtime.exs`.

```elixir
# application.ex
children = [
  MyApp.Repo,
  {Imison, Application.fetch_env!(:my_app, Imison)}
]

# config/runtime.exs
config :my_app, Imison,
  repo: MyApp.Repo,
  username: System.fetch_env!("IMISON_USER"),
  password: System.fetch_env!("IMISON_PASSWORD")
```

`repo`, `username` and `password` are required; every other option has a default (`Imison.Config`). Imison never reads environment variables itself: with `IMISON_USER` or `IMISON_PASSWORD` unset, the host's `System.fetch_env!` raises while loading `config/runtime.exs`. A missing, unknown, duplicate or wrongly typed option raises an `ArgumentError` from Imison. Either way the host fails to boot.

### Migration

Built today: Imison's tables come from an Ecto migration in the host's repo. Generate one with `mix ecto.gen.migration add_imison` and call `Imison.Migration`:

```elixir
defmodule MyApp.Repo.Migrations.AddImison do
  use Ecto.Migration

  def up, do: Imison.Migration.up(version: 1)
  def down, do: Imison.Migration.down(version: 1)
end
```

`up()` without a version migrates to the latest version. To keep the tables in a separate Postgres schema, pass `prefix:` to both calls (`Imison.Migration.up(version: 1, prefix: "imison")`; the schema is created when missing) and set the same `prefix` option in Imison's config (default `"public"`).

### Reporting rescued exceptions

Built today: crashes are captured without code changes; an exception the app rescues itself is tracked when it calls `Imison.report/3` in the `rescue`:

```elixir
try do
  MyApp.Orders.charge(order)
rescue
  exception ->
    Imison.report(exception, __STACKTRACE__, %{order_id: order.id})
    {:error, :charge_failed}
end
```

The metadata (a map or a keyword list, optional) is stored under `metadata` in the occurrence's context, filtered like every other context. `report/3` records in the background and always returns `:ok`: it never raises or blocks, and does nothing when no Imison instance runs. It reports to the default instance, named `Imison`; instances started with a custom `name` aren't reachable from `report/3` yet.

### Mounting the dashboard

Built today: import `Imison.Web.Router` in the host's router and call `imison_dashboard` inside a scope that pipes through the `:browser` pipeline (session and CSRF protection), at any path:

```elixir
# lib/my_app_web/router.ex
import Imison.Web.Router

scope "/" do
  pipe_through :browser

  imison_dashboard "/errors"
end
```

The host's endpoint needs the LiveView socket at `/live` with the session in its `connect_info`, as a Phoenix app generated with LiveView already has:

```elixir
socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]
```

The dashboard serves its own stylesheet, fonts and script under its path (`/errors/assets/…`, with digested URLs cached for a year), so the host's asset pipeline is unchanged and the page makes no third-party requests. Options: `imison_name:` names the Imison instance the dashboard reads (default `Imison`, for an instance started with a custom `name`), and `as:` names the route and its `live_session` (default `:imison_dashboard`; give each a different one to mount the dashboard twice in one router). The page raises when no instance runs under that name. There is no login yet (AUTH-02): until then, mount it only where the host already restricts access. Add `:imison` to `import_deps` in the host's `.formatter.exs` to format the macro without parentheses.

### Capture off in tests

Built today: set `enabled: false` in the host's test config, so tests that crash on purpose don't fill the database.

```elixir
# config/test.exs
config :my_app, Imison, enabled: false
```

The instance still starts and `Imison.config/1` still returns its config, but it attaches no logger or telemetry handler and starts no capture worker: crashes, Phoenix and Oban exceptions and `Imison.report/3` calls (which still return `:ok`) record nothing.

## Development

```sh
mix deps.get
mix test
mix test test/imison_test.exs:5   # a single test
mix format
mix credo --strict
mix check          # everything above, as CI and before a commit
```

Tests need Postgres at `postgres:postgres@localhost:5432`. `mix test` creates and migrates the `imison_test` database (`ecto.create` + `ecto.migrate`); it never drops it. With `MIX_TEST_PARTITION` set, the value is appended to the database name. After editing an unreleased `Imison.Migration` version, rebuild the database with `MIX_ENV=test mix ecto.drop`, then `mix test` (which creates and migrates it).

To see Imison in a host app, keep a small Phoenix app in `dev/`: its own Mix project with a path dependency on Imison (`{:imison, path: ".."}`). `dev/` is gitignored and not in the repo, so each maintainer keeps their own.

```sh
cd dev && mix deps.get && mix dev
```

`mix dev` creates and migrates the `imison_dev` database and serves http://localhost:4000, which links to routes that raise sample errors and to the dashboard. To mount the dashboard there, `dev/` needs what any host needs: a `Phoenix.PubSub` and `{Imison, ...}` in its supervision tree, `pubsub_server` and `live_view: [signing_salt: ...]` in its endpoint config, `Plug.Session` and the `/live` socket in its endpoint, and a `:browser` pipeline with `imison_dashboard "/errors"` in its router.

## Docs

- [`CONTEXT.md`](CONTEXT.md): domain language
- [`ARCHITECTURE.md`](ARCHITECTURE.md): what is built and where code goes
- [`docs/PROJECT.md`](docs/PROJECT.md): design and open decisions
- [`docs/STORIES.md`](docs/STORIES.md): user stories, the backlog
- [`docs/design/`](docs/design/): dashboard mockups (open `preview.html`); styles and fonts in `priv/static/`
- [`docs/adr/`](docs/adr/): architecture decisions
- [`docs/MEMORY.md`](docs/MEMORY.md): decision log
- [`.claude/README.md`](.claude/README.md): the Claude workflow
