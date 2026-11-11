# 🔧 Project settings for the Claude kit

<!--
Template. /init copies this to .claude/project.md and fills it in from the repo
and your answers. Don't edit the template per repo; edit project.md.
Every row is read by the commands and agents. "none" is a valid value: it
switches the related rule or check off.
-->

The kit's commands, agents and skills are generic Elixir/Phoenix. Everything specific to this repo lives here. Edit by hand when a fact changes.

## App

| Setting | Value |
|---|---|
| Name | <one line: what the app is> |
| Stage | <new (no domain code yet) / ongoing> |
| OTP app | `:<app>` |
| Context root | `lib/<app>/` (`<App>.*`) |
| Web root | `lib/<app>_web/` (`<App>Web.*`) |
| Repo | `<App>.Repo` |

## Git and tracking

| Setting | Value |
|---|---|
| Trunk branch | `<main / staging / …>` |
| Work on trunk | <Not allowed: `/implement` needs a feature branch / Allowed: `/implement` runs on the trunk> |
| Issue tracker | <Linear / GitHub Issues / Jira / None: tasks are local, in `.claude/work/<slug>/`> |
| Slug | <issue id + short name, e.g. `abc-123-member-prices` / short kebab-case name, e.g. `member-prices`> |
| Commit reference | <e.g. `Refs ABC-123` / `Closes #12` / None> |

## Databases

| Setting | Value |
|---|---|
| Dev DB (never migrate or roll back) | `<app>_dev` |
| Test DB (`mix test` migrates it) | `<app>_test` |
| Table prefixes (by owner) | <e.g. `stripe_` (Stripe sync), `supplier_` (read-only feed); app-owned tables unprefixed / None yet> |

## Tooling

Detected from `mix.exs` and `test/`. A tool marked "none" is never run or required by the agents.

| Tool | Value |
|---|---|
| Formatter | <`mix format` / `mix format` with Styler> |
| Linter | <`mix credo --strict` / none> |
| Background jobs | <Oban, workers in `lib/<app>/workers/` / none> |
| Test data | <ExMachina factory `<App>.Factory` in `test/support/factory.ex`, `insert(:factory)` / fixture modules in `test/support/fixtures/` / none yet> |
| External API mocks | <Mox: list the mocks defined in `test/test_helper.exs` / none> |
| API spec | <OpenApiSpex, schemas in `lib/<app>_web/specs/` / none> |
| Web UI | <LiveView / controllers + HEEx / JSON API only> |

## Tests

| Setting | Value |
|---|---|
| Endpoint test case | `<App>Web.ConnCase` |
| Data test case | `<App>.DataCase` |
| Endpoint test file | `test/<app>_web/controllers/<controller>/<action>_test.exs`, module `<App>Web.Controllers.<Controller>.<Action>Test` |
| LiveView test file | `test/<app>_web/live/<live_view>_test.exs` / n/a |
| Module test file | `test/<app>/…` mirroring `lib/<app>/…` |
| Test-data rules | <e.g. seeded reference data that must never be deleted / none> |
| Known flaky | <test paths, rerun once before investigating / none> |

## Web

| Setting | Value |
|---|---|
| Router | `lib/<app>_web/router.ex` |
| Path prefixes | <e.g. `/` (browser), `/api/v1` (JSON)> |
| Pipelines (reviewer checks placement) | <each pipeline and what it guards, e.g. `:browser` (session, CSRF), `:api` (JSON, no auth), `:authenticated_api` (bearer token)> |
| API docs for clients | <`docs/api/<endpoint>.md`, one per endpoint (created by `/implement` with the first one) / none (no external API clients)> |

## Access rules (reviewer fails on any leak)

<Bullet list of rules the reviewer must enforce, e.g.:
- A Customer sees only their own Orders.
- Member prices never reach a Customer without a premium Membership.
- A permission check that errors resolves to "denied".
Or: "None yet: no authentication.">

## Style overrides

The builder and reviewer enforce the kit's default Elixir style (`.claude/agents/builder.md`). List any default this repo turns off or changes; leave "none" to keep them all.

- <e.g. "`describe` blocks are allowed in tests." / "Comments in `lib/` are allowed for public API docs." / none>

## Docs

| Doc | Path |
|---|---|
| Domain language | `CONTEXT.md` |
| ADRs | `docs/adr/` |
| Architecture | `ARCHITECTURE.md` <(or the repo's existing architecture doc, if it already had one elsewhere)> |
| Decision log | `docs/MEMORY.md` |
