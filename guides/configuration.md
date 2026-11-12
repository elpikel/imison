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
    dashboard_url: "https://app.example.com/errors",
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
| `dashboard_url` | `nil` | The absolute URL where `imison_dashboard` is mounted, e.g. `https://app.example.com/errors`. Notifications link to the error under it; without it they have no links. |
| `release` | `nil` | A version label stored with each occurrence. |
| `retention_days` | `30` | How many days occurrences and hourly counts are kept. |
| `channels` | `[Imison.Notifications.Channels.Email]` when Swoosh is available, else `[]` | Notification channel modules. See [Notifications](notifications.md) and [Writing a notification channel](custom-channels.md). |
| `filter` | `~w(password token secret authorization cookie)` | A key containing one of these words (case-insensitively) has its value replaced with `[FILTERED]` in params, headers and metadata. Setting it replaces the list. |
| `ignore` | `[]` | Exception modules that are never recorded. |
| `enabled` | `true` | `false` turns capture, notifications and pruning off, for your test environment. |
| `prefix` | `"public"` | The Postgres schema that holds Imison's tables. |
| `name` | `Imison` | The instance's name, for running more than one. |

## The dashboard route

```elixir
# lib/my_app_web/router.ex
import Imison.Web.Router

scope "/" do
  pipe_through :browser

  imison_dashboard "/errors"
end
```

- **Path**: mount it at any path. If you change it, change `dashboard_url`
  too.
- **Pipeline**: the `:browser` pipeline must `fetch_session` and
  `protect_from_forgery`.
- **Socket**: your endpoint needs the LiveView socket with the session in its
  `connect_info`.
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

  def up, do: Imison.Migration.up(version: 1)
  def down, do: Imison.Migration.down(version: 1)
end
```

Migrations are versioned the way Oban's are. When a new Imison release
changes the schema, its changelog says so, and you add a migration that calls
`Imison.Migration.up(version: N)` with the new version. `up()` without a
version migrates to the latest one.

To keep the tables in their own Postgres schema, pass the same `prefix` to
the migration and to the config. The schema is created when it is missing:

```elixir
def up, do: Imison.Migration.up(version: 1, prefix: "imison")
def down, do: Imison.Migration.down(version: 1, prefix: "imison")
```

```elixir
config :my_app, Imison, prefix: "imison"
```

## Retention

Every hour, each running instance deletes occurrences and hourly counts older
than `retention_days`. The first run is a minute after start.

- **Errors are kept**: their counts and first and last seen dates stay on the
  dashboard after their occurrences are gone.
- **Batches**: rows go in batches of 10,000, so one run never holds long
  locks.
- **Several nodes**: every node may prune at the same time; each skips rows
  another node has locked.
- **Failures**: a failed run is logged under the `:imison` logger domain, and
  the next one runs an hour later.

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

## Logging

Imison logs its own problems, such as a failed recording, a failed delivery
or a failed prune, under the `:imison` logger domain, and never captures
them as errors. Elixir's `Logger` files them under `[:elixir, :imison]`. To
silence them, filter on that domain:

```elixir
:logger.add_primary_filter(:no_imison, {&:logger_filters.domain/2, {:stop, :sub, [:elixir, :imison]}})
```
