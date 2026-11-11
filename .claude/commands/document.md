---
description: Reconcile docs with reality — README, architecture doc, decision log. Run anytime. Also defines what the README and architecture doc contain (/init uses it).
argument-hint: [area to focus, optional]
model: sonnet
---

# document

Bring the human-facing docs in line with what actually exists. **Not a phase**
— a reconciler you run whenever code and docs have drifted. It detects drift;
it does not re-interview the project.

## Scope

- IN: README, architecture prose accuracy, the ubiquitous language
  (`CONTEXT.md`) against the code, curating the decision log, and the
  `CLAUDE.md` commands. Doc paths come from the *Docs* table in
  `.claude/project.md` (defaults: `ARCHITECTURE.md`, `docs/MEMORY.md`).
- OUT: making product/architecture **decisions** (that's
  `/brainstorm`). If reconciling reveals an undecided question, log it and point
  at the owning command — don't decide it here.

## Preflight

1. Read `.claude/project.md`, `CLAUDE.md`, `README.md`, `CONTEXT.md`, and
   the architecture doc and decision log named in `.claude/project.md`.
2. Read the actual code/structure; for a broad sweep, dispatch an `Explore`
   subagent for a structured map (contexts, schemas, routes, workers,
   external clients). Diff **docs vs. reality**, not docs vs. docs. Build a
   short drift list (claimed but absent, present but undocumented,
   contradictions).

## Interview

Minimal and targeted. Only ask when reconciliation is genuinely ambiguous
(e.g. "the architecture doc says Postgres, code uses SQLite — which is intended?").
No standing question bank. If nothing is ambiguous, ask nothing.

## Produce

### README

For a human arriving cold. Concise; link rather than repeat.

1. **What it is:** one or two sentences, in `CONTEXT.md` terms.
2. **Stack:** Elixir/Phoenix and versions (from `mix.exs`), and the tools that
   matter to a newcomer (Oban, LiveView, external services).
3. **Setup and run:** prerequisites (Elixir/Erlang versions, PostgreSQL),
   `mix setup`, `mix phx.server`, the URL.
4. **Configuration:** each environment variable the app reads
   (`config/runtime.exs`, `System.get_env`), what it's for, and what happens
   without it. Never real values.
5. **Tests and checks:** `mix test`, a single test, `mix precommit` (or the
   repo's equivalent).
6. **Docs:** links to `CONTEXT.md`, the architecture doc, `docs/adr/`, the API
   docs directory and the decision log, and to `.claude/README.md` for the
   Claude workflow.

### Architecture doc

How the system is built, for someone about to change it. Describe what
exists, never what's planned (that's `/brainstorm` and the ADRs).

1. **Overview:** what the system does and its main parts, in a few lines; a
   small diagram (Mermaid) when it helps.
2. **Contexts:** each context under the context root, what it owns (schemas,
   tables), and its public entry points. Which contexts call which.
3. **Web:** router scopes and pipelines, what each serves (LiveView,
   controllers + HEEx, JSON API), and how auth and access rules apply.
4. **Background work:** each worker, what triggers it (cron or another job),
   and what it writes.
5. **Data:** the main tables and their owners, table prefixes and which are
   external or read-only, notable views/materialized views.
6. **External services:** each client, its seam (behaviour) and how it's
   mocked in tests.
7. **Decisions:** links to the ADRs that shaped each area.

Scale it to the code: a new repo gets only the stack, the folder layout
(context root, web root, tests) and where new code goes; sections fill in as
code arrives.

Reconciling an existing doc: correct stale prose to match reality and fill
missing sections. Don't redesign. If reality diverged from a deliberate
decision, flag it for `/brainstorm` rather than rewriting the decision.

### Ubiquitous language

`CONTEXT.md`, in the `domain-modeling` skill's format. Add domain terms the
code uses but the glossary lacks, and flag (don't silently fix) code that
uses a term listed under `_Avoid_` or a glossary term that no longer appears
in the code. Whether to rename code or redefine a term is a decision for
`/brainstorm`.

### CLAUDE.md commands

Check the commands `CLAUDE.md` lists (setup, server, test, single test,
precommit) against `mix.exs` aliases and fix any that no longer exist or run.
Keep the `@AGENTS.md` import if `AGENTS.md` exists. Leave the rest of
`CLAUDE.md` alone: it's the user's.

### Decision log
Curated here: dedupe, order by date, keep it a tight
log of decisions-made-with-AI and why. This is the project's memory for
  Claude Code — terse, durable, not a changelog of everything.

## Hand off

Report the drift found and what you reconciled vs. flagged. Suggested next is
context-dependent — e.g. `/brainstorm` if a contradiction needs a real decision,
otherwise nothing.
