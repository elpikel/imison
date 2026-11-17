# Configuration

Imison is configured like any other child of your supervision tree. Put the
options in your app's config, then start the instance after your repo and
PubSub:

```elixir
# lib/my_app/application.ex
children = [
  MyApp.Repo,
  {Phoenix.PubSub, name: MyApp.PubSub},
  {Imison, Application.fetch_env!(:my_app, Imison)},
  MyAppWeb.Endpoint
]
```

```elixir
# config/config.exs
config :my_app, Imison,
  repo: MyApp.Repo,
  pubsub: MyApp.PubSub,
  mailer: MyApp.Mailer,
  from: "errors@example.com"

# config/runtime.exs
if config_env() == :prod do
  config :my_app, Imison,
    username: System.fetch_env!("IMISON_USER"),
    password: System.fetch_env!("IMISON_PASSWORD"),
    dashboard_url: "https://app.example.com/imison",
    release: System.get_env("RELEASE_SHA")
end
```

The options are validated when the app boots. A missing, unknown, duplicate
or wrongly typed option raises an `ArgumentError`, so a bad config fails the
boot instead of failing quietly later. `Imison.config/1` returns the running
instance's config.

## Options

| Option | Default | Description |
|---|---|---|
| `repo` | required | Your Ecto repo. Imison's tables live in its database, and its OTP app decides which stack frames are "your code". |
| `username` | required | The dashboard login. |
| `password` | required | The dashboard login. Only ever compared in constant time, never stored in the database or shown. |
| `pubsub` | `nil` | Your `Phoenix.PubSub` name. It makes open error lists update as errors happen; without it they refresh every 5 seconds. |
| `mailer` | `nil` | Your `Swoosh.Mailer` module, for the email channel. |
| `from` | `nil` | The sender address for the email channel. |
| `dashboard_url` | `nil` | The absolute URL where `imison_dashboard` is mounted, e.g. `https://app.example.com/imison`. Notifications link to the error under it, and the daily summary to the error list (`<dashboard_url>/errors`); without it they have no links. |
| `release` | `nil` | A version label stored with each occurrence. |
| `retention_days` | `30` | How many days occurrences and hourly counts are kept. |
| `channels` | `[Imison.Notifications.Channels.Email]` when Swoosh is available, else `[]` | Notification channel modules. See [Notifications](notifications.md) and [Writing a notification channel](custom-channels.md). |
| `filter` | `~w(password token secret authorization cookie)` | A key containing one of these words (case-insensitively) has its value replaced with `[FILTERED]` in params, headers and metadata. Setting it replaces the list. |
| `ignore` | `[]` | Exception modules that are never recorded. |
| `enabled` | `true` | `false` turns capture, analytics, notifications and pruning off, for your test environment. |
| `prefix` | `"public"` | The Postgres schema that holds Imison's tables. |
| `name` | `Imison` | The instance's name, for running more than one. |
| `analytics` | `false` | `true` counts your app's pageviews and visitors. See [Analytics](#analytics). |
| `analytics_retention_days` | `90` | How many days pageviews are kept. |
| `remote_ip_header` | `nil` | The request header holding the visitor's address behind a proxy, e.g. `"x-forwarded-for"`. Without it, analytics uses the connection's peer address. |

## The dashboard route

```elixir
# lib/my_app_web/router.ex
import Imison.Web.Router

scope "/" do
  pipe_through :browser

  imison_dashboard "/imison"
end
```

- **Path**: mount it at any path. If you change it, change `dashboard_url`
  too.
- **Pipeline**: the `:browser` pipeline must `fetch_session` and
  `protect_from_forgery`.
- **Socket**: your endpoint needs the LiveView socket with the session in its
  `connect_info`, plus `:peer_data`, `:user_agent` and `:x_headers` for
  [analytics](#analytics).
- **Pages**: `<path>/` is the overview, `<path>/errors` the error list,
  `<path>/analytics` the Analytics tab and `<path>/notifications` the
  Notifications screen. See [Using the dashboard](dashboard.md).
- **Assets**: the dashboard serves its own stylesheet, fonts and script under
  its path, so your asset pipeline is unchanged and the page makes no
  third-party requests.

Options:

- `imison_name:` the instance the dashboard reads (default `Imison`).
- `as:` the route and `live_session` name (default `:imison_dashboard`). Give
  each mount its own name to mount the dashboard twice in one router.

The dashboard carries its own login, so it is safe to mount in every
environment. You don't need to hide it behind dev-only routes.

## Migrations

Imison's tables come from a migration in your repo:

```elixir
defmodule MyApp.Repo.Migrations.AddImison do
  use Ecto.Migration

  def up, do: Imison.Migration.up(version: 2)
  def down, do: Imison.Migration.down(version: 1)
end
```

Migrations are versioned the way Oban's are. When a new Imison release
changes the schema, its changelog says so, and you add a migration that calls
`Imison.Migration.up(version: N)` with the new version. `up()` without a
version migrates to the latest one.

| Version | Changes |
|---|---|
| 1 | The error, notification and sign-in tables |
| 2 | `imison_pageviews` and `imison_salts`, for [analytics](#analytics) |

If you installed with version 1, add a migration with
`up(version: 2)` and `down(version: 2)`. New versions only add tables,
columns and indexes, so old and new code can run side by side during a
rolling deploy.

To keep the tables in their own Postgres schema, pass the same `prefix` to
the migration and to the config. The schema is created when it is missing:

```elixir
def up, do: Imison.Migration.up(version: 2, prefix: "imison")
def down, do: Imison.Migration.down(version: 1, prefix: "imison")
```

```elixir
config :my_app, Imison, prefix: "imison"
```

## Retention

Every hour, each running instance deletes occurrences and hourly counts older
than `retention_days`, pageviews older than `analytics_retention_days`, and
analytics' daily salts older than yesterday. The first run is a minute after
start. Pageviews are pruned even with `analytics: false`, so turning
analytics off doesn't keep old pageviews forever.

- **Errors are kept**: their counts and first and last seen dates stay on the
  dashboard after their occurrences are gone.
- **Batches**: rows go in batches of 10,000, so one run never holds long
  locks.
- **Several nodes**: every node may prune at the same time; each skips rows
  another node has locked.
- **Failures**: a failed run is logged under the `:imison` logger domain, and
  the next one runs an hour later. Until you add migration version 2, every
  run logs "Imison failed to prune old pageviews".

## Analytics

With `analytics: true`, Imison counts pageviews from inside your app, through
Phoenix's and LiveView's telemetry: no script, no cookie and no public
endpoint.

```elixir
config :my_app, Imison,
  analytics: true,
  remote_ip_header: "x-forwarded-for"
```

- **What counts**: a GET answered 200 with an HTML page, and a LiveView
  `navigate`, or a `patch` that changes the path. Bots (by user agent), the
  dashboard, other responses, assets and pages your CDN serves from its cache
  are not counted.
- **The LiveView socket** must share the visitor's details, which
  `mix imison.install` adds. Without them navigations aren't counted; page
  loads still are:

  ```elixir
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:peer_data, :user_agent, :x_headers, session: @session_options]],
    longpoll: [connect_info: [:peer_data, :user_agent, :x_headers, session: @session_options]]
  ```

- **`remote_ip_header`**: behind a proxy, the connection's address is the
  proxy's, and every visitor would look like one. Name the header your proxy
  sets; its first address is used, and a missing or unparsable header falls
  back to the peer address. No list of trusted proxies is checked: a spoofed
  header can only inflate the counts.
- **Only `x-*` headers reach the socket**: LiveView's `:x_headers` holds only
  headers starting with `x-`. With a header like `cf-connecting-ip`, page
  loads use it but navigations fall back to the peer address, so they count
  as a different visitor than the page load. Prefer an `x-` header such as
  `x-forwarded-for` or `x-real-ip`.
- **Privacy**: a visitor is a hash of the day's salt, the IP and the user
  agent; the IP and user agent are never stored, and the query string is
  dropped from the path. Each UTC day has its own salt, stored in the
  database so every node computes the same visitor, and deleted once it's
  older than yesterday.
- **Volume**: pageviews are buffered and written in batches of up to 100, at
  least once a second. If the buffer falls 10,000 pageviews behind, new ones
  are dropped rather than slowing your app; a crash loses the buffer.

The numbers are on the dashboard's [Analytics tab](dashboard.md#analytics).

## Running on several nodes

Imison works on several nodes without extra setup. Every node writes to the
same database:

- **Counts**: occurrence counts are incremented in SQL, so they add up
  correctly.
- **Notifications**: anything sent "once" (a reminder per hour, a summary per
  day) is claimed by a database write, so it goes out once however many nodes
  run.
- **Sign-in**: the throttle on failed sign-ins is shared through the
  database.
- **Live updates**: with clustered nodes and a shared `pubsub`, open lists
  update across nodes immediately. Without clustering, each list refreshes
  from the database every 5 seconds.

## Production checklist

- [ ] `IMISON_USER` and `IMISON_PASSWORD` are set; use a long random password.
- [ ] `dashboard_url` is set, so notifications link to the error.
- [ ] `mailer` and `from` are set, and the Email panel has recipients and is on.
- [ ] `release` is set from your build, so you can tell occurrences apart by
      deploy.
- [ ] `filter` covers your app's sensitive param and header names.
- [ ] `secret_key_base` is the same on every node, so a sign-in works on all
      of them.
- [ ] With `analytics: true` behind a proxy, `remote_ip_header` names an `x-*`
      header your proxy sets.

## Logging

Imison logs its own problems, such as a failed recording, a failed delivery
or a failed prune, under the `:imison` logger domain, and never captures
them as errors. Elixir's `Logger` files them under `[:elixir, :imison]`. To
silence them, filter on that domain:

```elixir
:logger.add_primary_filter(:no_imison, {&:logger_filters.domain/2, {:stop, :sub, [:elixir, :imison]}})
```
