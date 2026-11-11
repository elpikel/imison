# Imison

An error tracker you add to a Phoenix app as a library, installed the way Oban is: one dependency, one install task, one migration. It captures errors inside the host app, groups them, stores them in the app's own Postgres and serves a dashboard from the app's router.

**Status:** design stage. Only the `Imison` supervisor with validated config (read back with `Imison.config/1`), versioned migrations creating the six `imison_` tables (version 1) and the test database exist; see [`docs/PROJECT.md`](docs/PROJECT.md) for the design and user stories.

## Stack

Elixir 1.20, plain Mix library. Dependencies: `ecto_sql` and `postgrex` (Imison uses the host's repo). Planned: Phoenix LiveView for the dashboard, telemetry for capture; optional Swoosh (email), Oban (job-failure capture) and Igniter (installer).

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

`mix dev` creates and migrates the `imison_dev` database and serves http://localhost:4000, which links to routes that raise sample errors.

## Docs

- [`CONTEXT.md`](CONTEXT.md): domain language
- [`ARCHITECTURE.md`](ARCHITECTURE.md): what is built and where code goes
- [`docs/PROJECT.md`](docs/PROJECT.md): design and open decisions
- [`docs/STORIES.md`](docs/STORIES.md): user stories, the backlog
- [`docs/design/`](docs/design/): dashboard mockups (open `preview.html`); styles and fonts in `priv/static/`
- [`docs/adr/`](docs/adr/): architecture decisions
- [`docs/MEMORY.md`](docs/MEMORY.md): decision log
- [`.claude/README.md`](.claude/README.md): the Claude workflow
