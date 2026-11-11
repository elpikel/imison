---
description: Set up the Claude kit in an Elixir/Phoenix repo, new or ongoing — explore the code, detect the stack into .claude/project.md, write the README and architecture doc, and create the docs the flow needs. Re-run any time to fill gaps.
model: sonnet
---

# init

Make a freshly copied kit (`.claude/commands`, `.claude/agents`,
`.claude/skills`, `.claude/README.md`, `.claude/project.template.md`) work in
this repo. The kit is generic Elixir/Phoenix; everything repo-specific goes in
`.claude/project.md`, built from `.claude/project.template.md`.

Re-entrant: never overwrite a file a person wrote. On a re-run, fill in
missing or placeholder (`<…>`) values only, and report what was already there.

## 0. Stack check

The kit is for Elixir/Phoenix with Ecto. If there's no `mix.exs`, or it has
no `:phoenix` dependency, stop: `This kit is for Elixir/Phoenix projects;
<what you found> isn't supported.` A non-Phoenix Elixir app (library, CLI,
Nerves) gets the same message, with a note that the web-specific rows
would be empty.

## 1. Explore and detect

Read the repo, don't guess. Decide first whether it's **new** (a fresh
`mix phx.new`: no schemas, no migrations, only generated tests) or **ongoing**
(domain code exists).

For an **ongoing** repo, explore it before filling anything: dispatch an
`Explore` subagent (thoroughness "very thorough") to map the contexts and
their public functions, the Ecto schemas and the tables they own, the router
scopes and what each serves, the LiveViews and controllers, the background
workers and their schedules, external API clients and their seams, and the
supervision tree in `application.ex`. Ask it for a structured summary, not
file dumps; it feeds both `project.md` and the architecture doc.

Then fill every row of the template:

| Setting | Where to look |
|---|---|
| App name, OTP app, roots, Repo | `mix.exs`, `lib/`, `config/config.exs`, `README.md` |
| Trunk branch | `git symbolic-ref refs/remotes/origin/HEAD`, else the current branch if it's the only one, else ask |
| Dev and test DB | `config/dev.exs`, `config/test.exs` (`database:`) |
| Table prefixes | table names in `priv/repo/migrations/`, grouped by shared prefix; "None yet" for a new repo |
| Formatter | `.formatter.exs` (`plugins:` incl. `Styler`) |
| Linter | `:credo` in `mix.exs` deps |
| Background jobs | `:oban` in deps, workers directory |
| Test data | `:ex_machina` in deps and the factory module; else fixture modules in `test/support/` (e.g. `*_fixtures.ex` from `phx.gen`) |
| External API mocks | `Mox.defmock` in `test/test_helper.exs` |
| API spec | `:open_api_spex` in deps and the specs directory |
| Web UI | `live` routes / `*Live` modules, controllers with HEEx, JSON-only controllers |
| Test cases and file layout | `test/support/` (`*ConnCase`, `*DataCase`); existing files under `test/<app>_web/`. If both flat and per-action folders exist, use per-action folders (`<controller>/<action>_test.exs`). For a new repo, use the kit default. |
| Router, path prefixes, pipelines | `lib/<app>_web/router.ex` (`pipeline :name`, `scope "..."`), with a few words on what each pipeline guards |
| API docs directory | an existing `docs/api/` (or similar); else `docs/api/` if the repo serves an API to other clients, else none. Record the path only; `/implement` creates it with the first endpoint doc. |
| Access rules | auth and permission checks (`phx.gen.auth` scopes, plugs, `authorize`, role or plan checks such as `premium?`, scoping queries by user); ADRs that describe them. "None yet" if there's no auth. |
| Test-data rules | `priv/repo/seeds.exs` and seed migrations: reference data tests rely on and must never delete; confirm in *Ask*. "none" for a new repo. |
| Style overrides | an existing `CLAUDE.md`/`AGENTS.md` or `.credo.exs` that contradicts a kit default (e.g. tests use `describe`): propose it as an override |
| Docs | `CONTEXT.md`, `docs/adr/`, `ARCHITECTURE.md`, `docs/MEMORY.md`. If the repo already has an architecture doc elsewhere (e.g. `docs/architecture.md`), record that path and use it; never create a second one. |

## 2. Ask

Ask only what the repo can't answer, in one batch (AskUserQuestion):
- the issue tracker and its id format (e.g. Linear `ABC-123`) and commit
  reference (e.g. `Refs ABC-123`), or "none: local tasks";
- whether `/implement` may run on the trunk, or needs a feature branch;
- the trunk branch, if not detected;
- for a new repo, what the app is for, in a sentence (for the README,
  `CLAUDE.md` and `CONTEXT.md`), if `mix.exs` and the code don't say;
- access rules the reviewer must enforce, confirming what you found (skip
  for a repo with no auth);
- style overrides you proposed, if any;
- for an ongoing repo, terms the code uses inconsistently (e.g. `User` and
  `Customer` for the same thing, or one word for two things): which is the
  canonical term;
- seeded reference data that tests must never delete, confirming what you
  found (skip for a new repo);
- known flaky tests, if any (skip for a new repo).

## 3. Write

| File | Content |
|---|---|
| `.claude/project.md` | `.claude/project.template.md` with every `<…>` replaced by a detected or answered value, and the template's HTML comment removed. Tables, not prose. |
| `CLAUDE.md` | If missing: a one-line description of the app, the main commands (setup, server, test, single test, precommit if the alias exists) and a "Work tracking" section. If present: add the "Work tracking" section only. Either way, if `AGENTS.md` exists
(Phoenix 1.8 writes one) and `CLAUDE.md` doesn't import it, add an
`@AGENTS.md` line near the top, since Claude Code doesn't load `AGENTS.md` on
its own. The section says where tasks live (the tracker, or local in `.claude/work/<slug>/`), the flow `/brainstorm` → review → `/implement` → review → "yes, commit", and points to `.claude/README.md` and `.claude/project.md`. |
| `CONTEXT.md` | The ubiquitous language, in the `domain-modeling` skill's format (`.claude/skills/domain-modeling/CONTEXT-FORMAT.md`). If missing: for an ongoing repo, build it from the exploration — the domain nouns in schema and context names, status/enum values, and the words the UI and docs use — one tight definition each, with synonyms the code mixes under `_Avoid_` as you confirmed them in *Ask*; leave out framework and technical terms. For a new repo, the app name, its purpose, and only the terms the purpose names. If present: add missing terms, and list conflicts with the code instead of rewriting. |
| `docs/adr/` | If missing: create it with a `.gitkeep`. |
| `docs/MEMORY.md` | If missing: a header ("Dated decision log: what, why, what was rejected") and a first entry: `<today>: Claude kit set up.` |
| `README.md` | Follow *README* in `.claude/commands/document.md`. If missing, or still the `mix phx.new` boilerplate ("To start your Phoenix server…"), write it. If a person wrote it, don't rewrite it: list what's stale or missing and suggest `/document`. For a new repo, use the purpose from *Ask*. |
| `ARCHITECTURE.md` (or the existing doc's path) | Follow *Architecture doc* in `.claude/commands/document.md`, from the exploration. If present, don't rewrite it: list drift and suggest `/document`. For a new repo, write the short version: the stack, the folder layout and where new code goes. |
| `.gitignore` | Add `/.claude/work/` and `/.claude/settings.local.json` if they aren't there. |

Never commit.

## Hand off

The stage (new / ongoing), the stack and tools detected, the ones you asked
about, the tools switched off ("none"), the files created vs. already present,
and any drift found in a README or architecture doc you left alone. Then:
`Kit ready. Review .claude/project.md, then start a feature with /brainstorm <issue or idea>.`
