# Imision

An error tracker you add to a Phoenix app as a library, installed the way Oban is: one dependency, one install task, one migration. It captures errors inside the host app, groups them, stores them in the app's own Postgres and serves a dashboard from the app's router.

**Status:** design stage. Only the `mix new` skeleton exists; see [`docs/PROJECT.md`](docs/PROJECT.md) for the design and user stories.

## Stack

Elixir 1.20, plain Mix library. Planned: Phoenix LiveView for the dashboard, Ecto/Postgres through the host's repo, telemetry for capture; optional Swoosh (email), Oban (job-failure capture) and Igniter (installer).

## Installation (planned)

```elixir
# mix.exs of the host app
{:imision, "~> 0.1"},
{:igniter, "~> 0.5", only: [:dev]}
```

```sh
mix deps.get
mix imision.install
mix ecto.migrate
```

The installer, the manual steps and every option are in [`docs/PROJECT.md`](docs/PROJECT.md#installation).

## Configuration

The host app sets these in `config/runtime.exs`:

| Variable | For | Without it |
|---|---|---|
| `IMISION_USER` | Dashboard login username | Imision refuses to start |
| `IMISION_PASSWORD` | Dashboard login password | Imision refuses to start |

## Development

```sh
mix deps.get
mix test
mix test test/imision_test.exs:5   # a single test
mix format
mix credo --strict
mix check          # everything above, as CI and before a commit
```

## Docs

- [`CONTEXT.md`](CONTEXT.md): domain language
- [`ARCHITECTURE.md`](ARCHITECTURE.md): what is built and where code goes
- [`docs/PROJECT.md`](docs/PROJECT.md): design and open decisions
- [`docs/STORIES.md`](docs/STORIES.md): user stories, the backlog
- [`docs/design/`](docs/design/): dashboard mockups (open `preview.html`); styles and fonts in `priv/static/`
- [`docs/adr/`](docs/adr/): architecture decisions
- [`docs/MEMORY.md`](docs/MEMORY.md): decision log
- [`.claude/README.md`](.claude/README.md): the Claude workflow
