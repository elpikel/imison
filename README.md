# Imison

An error tracker you add to a Phoenix app as a library, installed the way Oban is: one dependency, one install task, one migration. It captures errors inside the host app, groups them, stores them in the app's own Postgres and serves a dashboard from the app's router.

**Status:** design stage. `mix imison.install` sets Imison up in a Phoenix app in one step. The `Imison` supervisor with validated config (read back with `Imison.config/1`), versioned migrations creating the seven `imison_` tables (version 1), error grouping and capture without code changes exist: crashed processes, Phoenix request exceptions and Oban job failures are recorded in the background, as are exceptions the app rescues and reports with `Imison.report/3`, except exceptions listed in `ignore`; `enabled: false` switches capture off. The dashboard mounts in the host's router with `imison_dashboard`, serves its own assets and asks for the configured login, slowing down repeated failed sign-ins, and lists errors by status (Unresolved, Resolved, Ignored, with counts), most recently seen first, with a search over kind, message and location, updating live when the host's PubSub is configured; errors can be resolved, ignored or marked unresolved from their detail page or in bulk from the list, and muted from their detail page so they stop notifying; a new error, and a resolved error that comes back, is emailed through the host's Swoosh mailer, and, when switched on, an unresolved error that keeps happening sends at most one reminder an hour, and a daily summary of the previous UTC day's new, returning and most frequent errors goes out at 08:00 UTC, with recipients, rules and a test email on the dashboard's Notifications screen; occurrences and hourly counts older than `retention_days` (default 30) are deleted every hour, keeping the errors themselves; see [`docs/PROJECT.md`](docs/PROJECT.md) for the design and user stories.

## Stack

Elixir 1.20, plain Mix library. Dependencies: `ecto_sql` and `postgrex` (Imison uses the host's repo), `telemetry` (Phoenix and Oban capture) and `phoenix_live_view` (the dashboard; brings `phoenix` and `phoenix_html`), required as with Oban Web. Optional: `swoosh` (the email channel; compiled only when the host depends on it) and `igniter` (`mix imison.install` makes the changes with it and prints them as manual steps without it; the host adds it, usually `only: [:dev]`). Test only: `phx_new` (the installer's tests generate a Phoenix project with it) and `bandit` (a local HTTP server the webhook tests post to). The webhook channel uses OTP's `:inets` (`:httpc`), `:ssl` and `:public_key`, listed in `extra_applications`. Oban is not a dependency: Imison handles its job-failure telemetry event when the host runs Oban.

## Installation

```elixir
# mix.exs of the host app
{:imison, "~> 0.1"},
{:igniter, "~> 0.8", only: [:dev]}
```

```sh
mix deps.get
mix imison.install      # or in one step, without editing mix.exs: mix igniter.install imison
mix ecto.migrate
```

`mix imison.install` is an Igniter task, like `mix oban.install`. It shows the changes and asks before writing them, and skips any change already there, so running it again changes nothing:

- `config/config.exs`: `config :my_app, Imison` with `repo` (the app's Ecto repo), `pubsub` (the endpoint's `pubsub_server`) and, when the app has a `MyApp.Mailer` module, `mailer`
- `config/runtime.exs`, inside `if config_env() == :prod do`: `username` and `password` from `System.fetch_env!("IMISON_USER")` and `System.fetch_env!("IMISON_PASSWORD")`
- `config/dev.exs`: the login `admin` with a random password generated at install time (sign in to the dev dashboard with it)
- `config/test.exs`: `enabled: false` and the login `test`/`test`, so tests record nothing
- the application's children: `{Imison, Application.fetch_env!(:my_app, Imison)}` after the repo and the PubSub
- a migration `priv/repo/migrations/<timestamp>_add_imison.exs` calling `Imison.Migration.up(version: 1)` and `down(version: 1)`
- the router: `import Imison.Web.Router` and `imison_dashboard "/errors"` in a `scope "/"` piped through `:browser`
- `.formatter.exs`: `:imison` in `import_deps`

After `mix ecto.migrate` the dashboard is at `/errors`. The app boots in dev and test without environment variables; in production set `IMISON_USER` and `IMISON_PASSWORD`, or the boot fails. To mount the dashboard at another path, change `"/errors"` in the router (and `dashboard_url`, if set). The options are described in the sections below; the full design is in [`docs/PROJECT.md`](docs/PROJECT.md#installation).

### Installing without Igniter

Without Igniter in the app's deps, `mix imison.install` changes no file: it prints these same steps with the app's name and modules filled in (`:my_app` and `MyApp` below), then the hint that adding `{:igniter, "~> 0.8", only: [:dev]}` makes the task do them for you. By hand:

1. `config/config.exs` (`pubsub` is the endpoint's `pubsub_server`; leave `mailer` out unless the app sends email through a Swoosh mailer):

   ```elixir
   config :my_app, Imison,
     repo: MyApp.Repo,
     pubsub: MyApp.PubSub,
     mailer: MyApp.Mailer
   ```

2. `config/runtime.exs`, inside `if config_env() == :prod do`:

   ```elixir
   config :my_app, Imison,
     username: System.fetch_env!("IMISON_USER"),
     password: System.fetch_env!("IMISON_PASSWORD")
   ```

3. `config/dev.exs`, with a dev password you pick:

   ```elixir
   config :my_app, Imison, username: "admin", password: "<a password you pick>"
   ```

4. `config/test.exs`, so tests record nothing:

   ```elixir
   config :my_app, Imison, enabled: false, username: "test", password: "test"
   ```

5. `lib/my_app/application.ex`, in the children list after `MyApp.Repo` and the `Phoenix.PubSub` child:

   ```elixir
   {Imison, Application.fetch_env!(:my_app, Imison)}
   ```

6. A migration: run `mix ecto.gen.migration add_imison` and fill it in:

   ```elixir
   defmodule MyApp.Repo.Migrations.AddImison do
     use Ecto.Migration

     def up, do: Imison.Migration.up(version: 1)
     def down, do: Imison.Migration.down(version: 1)
   end
   ```

7. `lib/my_app_web/router.ex`: import the macro after `use MyAppWeb, :router`, then mount the dashboard:

   ```elixir
   import Imison.Web.Router

   scope "/" do
     pipe_through :browser

     imison_dashboard "/errors"
   end
   ```

8. `.formatter.exs`: add `:imison` to `import_deps`, so `imison_dashboard` needs no parentheses:

   ```elixir
   import_deps: [:imison, ...]
   ```

Then run `mix ecto.migrate`.

## Configuration

Built today: `mix imison.install` does this for you. To do it by hand, add Imison to the host's supervision tree, after its repo, and set its options in `config/runtime.exs`.

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

Failed sign-ins are slowed down so the password can't be brute-forced. Each wrong username or password is stored in `imison_login_failures`, so every node counts the same failures. The first five failures within 15 minutes are free; after that, each attempt must wait 2^(failures − 5) seconds after the latest failure (1, 2, 4, … seconds), at most 5 minutes. An attempt made during the wait gets status 429 and "Too many failed sign-ins. Try again in N seconds.", and its username and password aren't checked at all, so even the right password is refused until the wait is over. A successful sign-in clears the stored failures; failures older than 15 minutes stop counting and are deleted at the next failed attempt. The count is global, not per IP address or username: someone guessing the password also makes the developer wait, but never for more than 5 minutes after their last attempt. Attempts are settled one at a time across all nodes, so a burst of parallel attempts can't slip past the wait. If the failures can't be read or written (the database is down), Imison logs it and refuses the sign-in with status 503 and "Sign-in is unavailable. Try again shortly.", without checking the username or password.

The dashboard's home page lists the errors of one status, most recently seen first (the 100 most recent; the foot says how many there are in all), each with its kind, message, location, number of occurrences and when it was last seen; an unresolved error that came back after being resolved is flagged "Back again", and a muted error "Muted". Tabs switch between Unresolved, Resolved and Ignored and show each one's count. The search box filters by text in the kind, message or location, case-insensitively and literally (`%` and `_` are plain characters), within the current tab; the counts follow the search. The status and the search are kept in the URL (`/errors?status=resolved&q=timeout`), so a filtered list can be bookmarked or shared. Tick rows (or Select all) to resolve, ignore or mark them unresolved at once from the bar above the list; an error's detail page has the same buttons for that one error, plus "Mute notifications" ("Unmute" once muted). Other open lists follow the change when the host's PubSub is configured.

### Live updates

Built today: an open error list updates without a reload: a new error appears, a repeated one gets its new count, last seen and heat strip, and the tab counts follow, while the selection and the search stay. The top bar shows a "Live" indicator whose title says how the list updates. Set `pubsub` to the host's `Phoenix.PubSub` name (the one its endpoint's `pubsub_server` uses) for updates as errors happen:

```elixir
config :my_app, Imison,
  repo: MyApp.Repo,
  pubsub: MyApp.PubSub,
  username: System.fetch_env!("IMISON_USER"),
  password: System.fetch_env!("IMISON_PASSWORD")
```

Each recorded occurrence is broadcast on that PubSub under a topic per Imison instance; the list reloads at most once a second however many errors arrive, so a crash storm doesn't flood the browser. Broadcasts reach lists open on other nodes only when the nodes are clustered and share the PubSub, so an open list also refreshes from the database every 5 seconds whenever it can't count on them: without `pubsub` (the default; nothing is broadcast), while its node has no connected nodes, or when no PubSub runs under the configured name (failed broadcasts and subscriptions are logged and recording is unaffected). Its indicator then reads "Refreshes from the database every few seconds." A list on a node with connected nodes relies on the broadcasts alone; if the node loses them, the list starts refreshing at its next 5-second check. Clustering is never required: unclustered nodes all write to the same database, and their lists catch up within the interval.

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

The email is plain text: the subject is `[Imison] New error: <kind> in <location>`, or `[Imison] Came back: <kind> in <location>` for a resolved error that happened again, whose body also says it was resolved and happened again and when (UTC), or `[Imison] Still happening: <kind> in <location>` for the reminder about an unresolved error that keeps happening, whose body says when it was last seen. Every body has the kind, message, location, number of occurrences, when it was first seen and, with `dashboard_url`, the link (`<dashboard_url>/errors/<id>`); without `dashboard_url` it is sent without a link. Only the first occurrence of an error and the occurrence that reopens a resolved error send one. With "An error keeps happening" switched on (off by default), other occurrences of an unresolved error send a reminder at most once per error per clock hour (UTC) of the error's last seen time, however many nodes record them; an ignored error happening again sends nothing. A muted error sends nothing for any trigger, whatever the rules say, while it stays listed and counted under its status; unmuting it restores its notifications from its next occurrence. Switching it on mid-hour reaches an error that already happened in that hour from the next hour.

With "Daily summary" switched on (off by default), one email goes out once 08:00 UTC has passed, `[Imison] Daily summary for <date>`, covering the previous UTC day in three sections: "New errors" (first seen that day), "Came back" (resolved errors that came back that day) and "Most frequent" (the five errors that occurred most that day). Each line has the error's kind, message, that day's number of occurrences, location and, with `dashboard_url`, its link; a section lists at most 20 errors and then says how many more there were, with the dashboard's link. Muted errors are listed too: the summary isn't an alert. A day with nothing in any section sends nothing. However many nodes run, each day's summary is sent once per channel. Switching it on at any time of the day sends the previous day's summary within a minute, if it wasn't sent yet.

Set up channels and rules on the dashboard's Notifications screen (`<path>/notifications`, linked from the top bar). It shows one panel per module in `channels`, each with its settings, a switch that turns the channel on or off, "Save changes" and "Send test", and below them one set of rules, "Send a notification when": "A new error appears", "A resolved error comes back", "An error keeps happening" and "Daily summary", saved with "Save rules". The rules apply to every channel that's on; they aren't per channel. On the Email panel, enter the addresses separated by commas or new lines, switch it on and save. Each address must look like `local@domain` (the domain isn't looked up); an invalid one is named under the field and nothing is saved. Saving a panel stores that channel's row, on or off, with its settings; a channel never saved is off. "Send test" sends a test message (for email, `[Imison] Test email`) through that channel alone with the panel's values (saved or not) right away and shows "Test sent through Email." or the channel's error (a mailer that raises, or a missing `mailer` or `from`, shows an error too and is logged); a test is not recorded in `imison_deliveries`. The Email panel shows the configured mailer and sender, or how to set them. When `channels` is empty (by default, when the host doesn't depend on Swoosh), the screen says email isn't available and how to enable it.

Nothing is sent through a channel until it is saved switched on with valid settings, or when the trigger's rule (`new`, `regression`, `still_happening` or `digest`) is switched off (a trigger never saved is on for `new` and `regression`, off for `still_happening` and `digest`). The settings live in `imison_channels` (one row per channel type) and `imison_rules`. Emails are sent in the background under Imison's own `Task.Supervisor`, so a slow mailer never holds up capture. Each attempt is recorded in `imison_deliveries` as `sent` or `failed` (a reminder also with its hour as `period`, a daily summary with no error and its day as `period`); a mailer that returns an error or raises (or a missing `mailer` or `from`) is logged under the `:imison` logger domain, and the error is recorded as usual.

`channels` lists the channel modules (default `[Imison.Notifications.Channels.Email]`, or `[]` when the host doesn't depend on Swoosh). A module listed there must implement the `Imison.Notifications.Channel` behaviour (`type/0`, `validate_config/1`, `deliver/3`), or Imison refuses to start. Besides messages about one error, `deliver/3` receives the daily summary when "Daily summary" is on: an `Imison.Notifications.Message` with `trigger: :digest`, its error fields `nil` and `summary` set; a channel must render it or skip it by returning `:ok`. It also receives the test message (`trigger: :test`, error fields `nil`) when "Send test" is clicked on its panel.

#### Custom channels

A host app adds a channel by writing a module that implements `Imison.Notifications.Channel` and listing it in `channels`; it gets its own panel on the Notifications screen and receives every notification the rules allow, as the email channel does. Three optional callbacks shape its panel:

- `label/0`: the panel's title (default: `type/0`).
- `config_fields/0`: the settings the panel asks for, in order (default: none), each `%{name: "service_url", label: "Service URL", type: :url, hint: "Where alerts go."}` (`hint` optional). `type` is `:recipients` (a textarea of values separated by commas or new lines, stored as a list of strings), `:text` or `:url` (an input, stored as a trimmed string, removed when blank) or `:secret` (a password input, stored as a trimmed string).
- `describe/1`: a line under the title, given the instance's config (default: none).

```elixir
defmodule MyApp.PagerChannel do
  @behaviour Imison.Notifications.Channel

  @impl true
  def type, do: "pager"

  @impl true
  def label, do: "Pager"

  @impl true
  def config_fields do
    [
      %{name: "service_url", label: "Service URL", type: :url},
      %{name: "token", label: "API token", type: :secret}
    ]
  end

  @impl true
  def validate_config(%{"service_url" => "https://" <> _, "token" => _token}), do: :ok
  def validate_config(_config), do: {:error, service_url: "must start with https://", token: "can't be blank"}

  @impl true
  def deliver(%Imison.Notifications.Message{trigger: :digest}, _config, _imison_config), do: :ok
  def deliver(message, %{"service_url" => url, "token" => token}, _imison_config), do: MyApp.Pager.alert(url, token, message)
end
```

The settings are stored in `imison_channels.config` (jsonb) under the field names, in the row for the channel's `type/0`, and handed to `validate_config/1` and `deliver/3` as that map with string keys. Saving a panel calls `validate_config/1` first: its `{:error, [field: "reason"]}` reasons are shown under the fields with those names (others under the panel's fields) and nothing is stored. A channel is used only while its row is on and its stored settings pass `validate_config/1`. A `:secret` field is never shown back: the panel says a value is set, and leaving it blank keeps the stored value, both when saving and when sending a test; ticking the "Remove" box next to a set secret clears it instead (a new value typed in wins), again both when saving and when sending a test. Settings in the stored row that the fields don't list are kept when the panel is saved.

#### Webhook

`Imison.Notifications.Channels.Webhook` POSTs each notification as JSON to a URL you choose. It isn't in the default `channels`; add it:

```elixir
{Imison,
 repo: MyApp.Repo,
 # ...
 channels: [Imison.Notifications.Channels.Email, Imison.Notifications.Channels.Webhook]}
```

Then on the Notifications screen fill the Webhook panel's "URL" (`http://` or `https://`; anything else is refused under the field) and, optionally, a "Signing secret", switch it on and save. "Send test" POSTs a message with `"trigger": "test"`.

The body is the `Imison.Notifications.Message` as a JSON object (`content-type: application/json`), times in ISO 8601 and unset fields as `null`:

```json
{
  "trigger": "new",
  "error_id": 42,
  "kind": "ArgumentError",
  "message": "invalid order id",
  "location": "MyApp.Orders.fetch/1 (lib/my_app/orders.ex:12)",
  "occurrence_count": 1,
  "first_seen_at": "2026-11-12T09:30:00.000000Z",
  "last_seen_at": "2026-11-12T09:30:00.000000Z",
  "regressed_at": null,
  "url": "https://app.example.com/errors/errors/42",
  "summary": null
}
```

`trigger` is `new`, `regression`, `still_happening`, `digest` or `test`. For the daily summary (`digest`) the error fields are `null` and `summary` holds `date`, `url` and the sections `new`, `came_back` and `most_frequent`, each `{"lines": [...], "total": n}` with lines of `error_id`, `kind`, `message`, `location`, `count` and `url`.

With a signing secret, each request also carries `x-imison-timestamp` (Unix seconds) and `x-imison-signature: sha256=<hex>`, the lowercase hex HMAC-SHA256 of `<timestamp>.<raw body>` keyed with the secret. To verify it, recompute the HMAC over the raw request body (before any JSON parsing), compare in constant time and reject old timestamps to stop replays:

```elixir
def verify(raw_body, timestamp, "sha256=" <> signature, secret) do
  expected = :hmac |> :crypto.mac(:sha256, secret, timestamp <> "." <> raw_body) |> Base.encode16(case: :lower)
  fresh? = abs(System.system_time(:second) - String.to_integer(timestamp)) <= 300

  fresh? and Plug.Crypto.secure_compare(expected, signature)
end
```

A 2xx answer counts as sent. Any other status (redirects aren't followed) fails the delivery with `{:http_status, status}`; a connection that is refused, fails TLS verification, takes longer than 5 seconds to open or longer than 5 more seconds to answer fails it with the reason, so one delivery takes at most about 10 seconds. Deliveries run in the background, but "Send test" waits for the answer, so the screen is busy for up to those 10 seconds with a slow endpoint. A failed delivery is logged and recorded as `failed` like any other; the logged reason never contains the URL or the secret. Requests go through OTP's `:httpc` (default profile, with every option set per request) with TLS peer and hostname verification against the system's CA certificates (`:public_key.cacerts_get/0`); Imison adds no HTTP client dependency.

### Retention

Built today: every hour each running instance deletes occurrences, and hourly counts, older than `retention_days` (default 30), so the tables stay small. The errors themselves are kept, with their occurrence count and first and last seen; the detail page of an error whose occurrences are all gone shows its summary without stack trace or context.

```elixir
# config/runtime.exs
config :my_app, Imison,
  repo: MyApp.Repo,
  username: System.fetch_env!("IMISON_USER"),
  password: System.fetch_env!("IMISON_PASSWORD"),
  retention_days: 14
```

The first run is a minute after the instance starts. Rows go in batches of 10 000, so one run never holds long locks, and every node may run it at the same time: each deletes rows the others haven't locked. A failed run (e.g. the database is unavailable) is logged under the `:imison` logger domain and the next one runs an hour later. With `enabled: false` nothing is pruned.

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
