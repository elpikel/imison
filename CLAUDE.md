# Imision

Error tracker shipped as a Hex library that runs inside a host Phoenix app, stores errors in the host's Postgres and serves a LiveView dashboard from the host's router. This repo is a plain Mix library, not a Phoenix app. Design and scope: `docs/PROJECT.md`. Domain language: `CONTEXT.md`.

## Commands

- `mix deps.get`: setup
- `mix check`: run before committing: compile with warnings as errors, unused deps, format check, Credo strict, tests
- `mix test`: all tests
- `mix test path/to/test.exs:LINE`: a single test
- `mix format`: format (Styler plugin)
- `mix credo --strict`: lint (includes ExSlop checks)

## Agent skills

### Work tracking

No issue tracker: stories and tasks live locally in `.claude/work/<slug>/` (ignored by git), with the backlog in `docs/STORIES.md`. Flow: `/brainstorm` → review → `/implement` (uncommitted, on a feature branch off `main`) → review → "yes, commit". See `.claude/README.md`; repo settings in `.claude/project.md`.

### Domain docs

Single-context layout: one `CONTEXT.md` + `docs/adr/` at the repo root.
