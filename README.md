# Imison

An error tracker you add to a Phoenix app as a library, installed the way Oban is: one dependency, one install task, one migration. It captures errors inside the host app, groups them, stores them in the app's own Postgres and serves a dashboard from the app's router.

**Status:** design stage. The `Imison` supervisor with validated config (read back with `Imison.config/1`), versioned migrations creating the six `imison_` tables (version 1), error grouping and capture without code changes exist: crashed processes, Phoenix request exceptions and Oban job failures are recorded in the background, as are exceptions the app rescues and reports with `Imison.report/3`, except exceptions listed in `ignore`; `enabled: false` switches capture off. The dashboard mounts in the host's router with `imison_dashboard`, serves its own assets and asks for the configured login, and lists errors by status (Unresolved, Resolved, Ignored, with counts), most recently seen first, with a search over kind, message and location, updating live when the host's PubSub is configured; errors can be resolved, ignored or marked unresolved from their detail page or in bulk from the list; a new error, and a resolved error that comes back, is emailed through the host's Swoosh mailer, with recipients, rules and a test email on the dashboard's Notifications screen; see [`docs/PROJECT.md`](docs/PROJECT.md) for the design and user stories.

## Stack

Elixir 1.20, plain Mix library. Dependencies: `ecto_sql` and `postgrex` (Imison uses the host's repo), `telemetry` (Phoenix and Oban capture) and `phoenix_live_view` (the dashboard; brings `phoenix` and `phoenix_html`), required as with Oban Web. Optional: `swoosh` (the email channel; compiled only when the host depends on it). Planned: optional Igniter (installer). Oban is not a dependency: Imison handles its job-failure telemetry event when the host runs Oban.

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

`repo`, `username` and `password` are required; every other option has a default (`Imison.Config`). `username` and `password` are the dashboard login: they live only in config, are never stored in the database, and a sign-in is checked against both with `Plug.Crypto.secure_compare/2`. Imison never reads environment variables itself: with `IMISON_USER` or `IMISON_PASSWORD` unset, the host's `System.fetch_env!` raises while loading `config/runtime.exs`. A missing, unknown, duplicate or wrongly typed option raises an `ArgumentError` from Imison. Either way the host fails to boot.

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

Built today: import `Imison.Web.Router` in the host's router and call `imison_dashboard` inside a scope that pipes through the `:browser` pipeline, at any path. That pipeline must `fetch_session` and `protect_from_forgery`, as the one `mix phx.new` generates does: the login lives in the host's session and its forms carry the host's CSRF token.

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

The dashboard serves its own stylesheet, fonts and script under its path (`/errors/assets/…`, with digested URLs cached for a year), so the host's asset pipeline is unchanged and the page makes no third-party requests. Options: `imison_name:` names the Imison instance the dashboard reads (default `Imison`, for an instance started with a custom `name`), and `as:` names the route and its `live_session` (default `:imison_dashboard`; give each a different one to mount the dashboard twice in one router). The page raises when no instance runs under that name. Add `:imison` to `import_deps` in the host's `.formatter.exs` to format the macro without parentheses.

Every dashboard page asks for the login set by the `username` and `password` options: without it, a visitor is redirected to the login page at `<path>/login` (`/errors/login` above), which, with its assets, is the only page open to everyone. A correct username and password redirect to the dashboard; a wrong one shows "Wrong username or password." and signs nothing in. Signing in stores a value derived from the configured username and password, keyed with the endpoint's `secret_key_base`, in the host's session cookie (never the credentials, and nothing in the database), so a visitor stays signed in on every node that shares `secret_key_base`, until the session ends or they sign out. The Sign out button in the top bar posts to `<path>/logout`, which clears that value from that browser's session and returns to the login page; it ends only that browser's session. Because the value depends only on the username, password and `secret_key_base`, a copy of the cookie stays valid elsewhere: changing the password (and restarting) is the only way to end every session.

The dashboard's home page lists the errors of one status, most recently seen first (the 100 most recent; the foot says how many there are in all), each with its kind, message, location, number of occurrences and when it was last seen; an unresolved error that came back after being resolved is flagged "Back again". Tabs switch between Unresolved, Resolved and Ignored and show each one's count. The search box filters by text in the kind, message or location, case-insensitively and literally (`%` and `_` are plain characters), within the current tab; the counts follow the search. The status and the search are kept in the URL (`/errors?status=resolved&q=timeout`), so a filtered list can be bookmarked or shared. Tick rows (or Select all) to resolve, ignore or mark them unresolved at once from the bar above the list; an error's detail page has the same buttons for that one error. Other open lists follow the change when the host's PubSub is configured.

### Live updates

Built today: set `pubsub` to the host's `Phoenix.PubSub` name (the one its endpoint's `pubsub_server` uses) and an open error list updates without a reload: a new error appears, a repeated one gets its new count, last seen and heat strip, and the tab counts follow. The top bar then shows a "Live" indicator.

```elixir
config :my_app, Imison,
  repo: MyApp.Repo,
  pubsub: MyApp.PubSub,
  username: System.fetch_env!("IMISON_USER"),
  password: System.fetch_env!("IMISON_PASSWORD")
```

Each recorded occurrence is broadcast on that PubSub under a topic per Imison instance; the list reloads at most once a second however many errors arrive, so a crash storm doesn't flood the browser. Without `pubsub` (the default) nothing is broadcast, there is no indicator and the list shows new errors when the page is reloaded. If no PubSub runs under that name, failed broadcasts and subscriptions are logged, recording is unaffected and the list still works, without the indicator or live updates. Updates reach lists open on other nodes only when the nodes share the PubSub (are clustered); see MN-04 in `docs/STORIES.md`.

### Email on a new or returning error

Built today: when an error is seen for the first time, or a resolved error happens again, Imison emails it through the host's own Swoosh mailer. Set `mailer` (the host's `Swoosh.Mailer` module) and `from`, and optionally `dashboard_url`, the absolute URL where `imison_dashboard` is mounted, so the email links to the error's page:

```elixir
config :my_app, Imison,
  repo: MyApp.Repo,
  mailer: MyApp.Mailer,
  from: "errors@example.com",
  dashboard_url: "https://app.example.com/errors",
  username: System.fetch_env!("IMISON_USER"),
  password: System.fetch_env!("IMISON_PASSWORD")
```

The email is plain text: the subject is `[Imison] New error: <kind> in <location>`, or `[Imison] Came back: <kind> in <location>` for a resolved error that happened again, whose body also says it was resolved and happened again and when (UTC). Both bodies have the kind, message, location, number of occurrences, when it was first seen and, with `dashboard_url`, the link (`<dashboard_url>/errors/<id>`); without `dashboard_url` it is sent without a link. Only the first occurrence of an error and the occurrence that reopens a resolved error send one; other repeats, and an ignored or unresolved error happening again, send nothing.

Set the recipients and rules on the dashboard's Notifications screen (`<path>/notifications`, linked from the top bar): enter the addresses separated by commas or new lines, switch "A new error appears" and "A resolved error comes back" on or off, and save. Each address must look like `local@domain` (the domain isn't looked up); an invalid one is named under the field and nothing is saved. Saving stores the email channel, enabled, and both rules in one transaction. "Send test email" sends `[Imison] Test email` to the addresses in the form (saved or not) right away and shows "Test email sent to …" or the mailer's error (a mailer that raises, or a missing `mailer` or `from`, shows an error too and is logged); a test email is not recorded in `imison_deliveries`. The screen shows the configured mailer and sender, or how to set them. When the email channel isn't in `channels` (the host doesn't depend on Swoosh), the screen says email isn't available and how to enable it.

Nothing is sent until recipients are saved, or when the trigger's rule (`new` or `regression`) is switched off (a trigger never saved is on for `new` and `regression`). The settings live in `imison_channels` (one row per channel type) and `imison_rules`. Emails are sent in the background under Imison's own `Task.Supervisor`, so a slow mailer never holds up capture. Each attempt is recorded in `imison_deliveries` as `sent` or `failed`; a mailer that returns an error or raises (or a missing `mailer` or `from`) is logged under the `:imison` logger domain, and the error is recorded as usual.

`channels` lists the channel modules (default `[Imison.Notifications.Channels.Email]`, or `[]` when the host doesn't depend on Swoosh). A module listed there must implement the `Imison.Notifications.Channel` behaviour (`type/0`, `validate_config/1`, `deliver/3`), or Imison refuses to start.

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
