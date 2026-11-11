# 🔧 Project settings for the Claude kit

The kit's commands, agents and skills are generic Elixir/Phoenix. Everything specific to this repo lives here. Edit by hand when a fact changes.

Imision is a **library**, not a Phoenix app: it has no endpoint, router or repo of its own. The host app supplies them; during development the Phoenix app under `dev/` (not built yet) plays the host. Rows below that a Phoenix app would fill point at the host or at `dev/`.

## App

| Setting | Value |
|---|---|
| Name | Imision: error tracker library that runs inside a host Phoenix app (`docs/PROJECT.md`) |
| Stage | new (no domain code yet) |
| OTP app | `:imision` |
| Context root | `lib/imision/` (`Imision.*`) |
| Web root | `lib/imision/web/` (`Imision.Web.*`) |
| Repo | none of its own: the host's repo, passed as the `repo:` option; the `dev/` app's repo in development |

## Git and tracking

| Setting | Value |
|---|---|
| Trunk branch | `main` |
| Work on trunk | Not allowed: `/implement` needs a feature branch |
| Issue tracker | None: tasks are local, in `.claude/work/<slug>/`; the backlog is `docs/STORIES.md` |
| Slug | story ID + short name, e.g. `cap-04-async-capture` |
| Commit reference | None |

## Databases

| Setting | Value |
|---|---|
| Dev DB (never migrate or roll back) | none yet (the `dev/` host app's database, once it exists) |
| Test DB (`mix test` migrates it) | none yet (a test repo is added with the first schema) |
| Table prefixes (by owner) | `imision_` (all Imision-owned, created in the host's database by `Imision.Migration`) |

## Tooling

| Tool | Value |
|---|---|
| Formatter | `mix format` with Styler |
| Linter | `mix credo --strict` (with the ExSlop plugin) |
| Background jobs | none (Imision uses its own `Task.Supervisor` and a pruner process; Oban is only an optional host integration) |
| Test data | none yet |
| External API mocks | none |
| API spec | none |
| Web UI | LiveView (dashboard mounted in the host router by `imision_dashboard`); design reference in `docs/design/` (mockups styled by `priv/static/app.css`): reuse their markup and class names, no CSS framework, no third-party requests (fonts are bundled in `priv/static/fonts/`) |

## Tests

| Setting | Value |
|---|---|
| Endpoint test case | n/a (no controllers; LiveView tests go through a test endpoint, added with the first LiveView) |
| Data test case | none yet (added with the first schema) |
| Endpoint test file | n/a |
| LiveView test file | `test/imision/web/live/<live_view>_test.exs` |
| Module test file | `test/imision/…` mirroring `lib/imision/…` |
| Test-data rules | none |
| Known flaky | none |

## Web

| Setting | Value |
|---|---|
| Router | `lib/imision/web/router.ex` (the `imision_dashboard` macro; the host's router mounts it) |
| Path prefixes | chosen by the host, e.g. `/errors` |
| Pipelines (reviewer checks placement) | the host's `:browser` (session, CSRF), then Imision's own login check on every dashboard route except the login page |
| API docs for clients | none (no external API clients) |

## Access rules (reviewer fails on any leak)

- Every dashboard route and LiveView requires the Imision login, except the login page itself.
- Credentials are compared only with `Plug.Crypto.secure_compare/2`; they come from config, never stored in the database.
- Keys in the `filter` option (default `password`, `token`, `secret`, `authorization`, `cookie`) are replaced with `[FILTERED]` before an occurrence is stored.
- Capture never blocks or crashes the host: handlers only build the event and cast it; a full queue drops the event.
- Errors raised inside Imision are logged, never captured.
- "Only once" actions (notifications, digests, reminders) are decided by a database write, never by node-local state.

## Style overrides

- none

## Docs

| Doc | Path |
|---|---|
| Domain language | `CONTEXT.md` |
| ADRs | `docs/adr/` |
| Architecture | `ARCHITECTURE.md` |
| Design and backlog | `docs/PROJECT.md` |
| Dashboard design | `docs/design/` |
| Decision log | `docs/MEMORY.md` |
