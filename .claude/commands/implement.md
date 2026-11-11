---
description: Implement a reviewed /brainstorm plan task by task — builder writes tests and code, reviewer gates — and hand the uncommitted work to you for review; commits are split only after you accept.
argument-hint: [feature slug, optional if only one plan exists]
model: sonnet
---

# implement

> 🎯 **Design for change.** Each task's diff should be small, local, and
> behind a stable seam, so each task reviews (and later commits) on its own.

Running this command is the user's sign-off on the **plan**, not on the code.
You are the orchestrator: you dispatch the builder and reviewer and hand the
work over **uncommitted**. You do **not** write or review code yourself, and
you never commit until the user has reviewed the work and says yes to the
commit split (see *After review*).

Repo facts (trunk, dev DB, tracker, API paths) are in `.claude/project.md`.
Pass it to every builder and reviewer.

## Preflight

1. **The plan.** `.claude/work/<slug>/` from `$ARGUMENTS`, else the only
   folder in `.claude/work/` whose `plan.md` has `Status: planned`,
   `implementing` or `implemented`. Read `plan.md` and `stories.md`. If none,
   or several and none named, list them and stop.
   - **Resuming** (`implementing`, an interrupted run): ticked tasks are
     done; start at the first unticked one. Their files are already in the
     tree, so treat them as the work's, not as unrelated changes.
   - **Coming back to review** (`implemented`): skip the rest of *Preflight*,
     the loop and *Finish*; read `review.md` and the `## Commit split` from
     the task folder and go to *After review*.
2. **The branch.** The work lands on the current branch. If it is the trunk
   branch and `.claude/project.md` doesn't say *Work on trunk: Allowed*, stop:
   `Create a feature branch from <trunk> first.` Never switch or create
   branches yourself.
3. **The tree.** Run `git status --short`. Unrelated changes are fine and are
   never committed, but if one touches a file a task owns, list it and ask
   whether to proceed. Note the starting state so the hand-over can tell the
   task's changes apart from what was already there.
4. Set `plan.md` to `Status: implementing`.

## The loop

For each unticked task in `plan.md`, in order:

1. **Build.** Dispatch a `builder` subagent (`subagent_type: builder`) with
   the task text, its acceptance criteria from `stories.md`, the files it
   owns and its test files. The builder writes the task's tests first (via
   the `bdd-specs` skill, red), then the code, and returns the files it
   changed or created.
2. **Review.** Dispatch a `reviewer` subagent (`subagent_type: reviewer`)
   with the task text, its acceptance criteria and the builder's file list.
   It returns `PASS` or `FAIL` with findings.
3. **Recurse.** On `FAIL`, send the findings to a fresh `builder` for the
   same task, then review again, until `PASS`. If a task can't pass after
   repeated attempts, stop and report rather than handing over degraded code.
   **Docs-only tasks** (the task owns only Markdown files): the builder writes
   the doc instead of tests and code, and the reviewer checks it against the
   criteria instead of running the suite. If the doc states facts about
   third-party services, research them first (a `general-purpose` subagent
   with web access writes sourced notes into `.claude/work/<slug>/`), because
   the builder and reviewer have no web access.
4. **Smoke the entry point** for wire tasks: a request through the router in
   the endpoint test case, the LiveView via `live/2`, or `Worker.perform/1`, asserting the criteria's
   response or side effect. Unit tests alone don't count.
5. **Record the task.** Note the files the builder changed or created (and,
   for a file several tasks touch, which hunks belong to this task), then tick
   the task in `plan.md`. Do **not** stage or commit. Next task.

## API docs

Skip this section if `.claude/project.md` lists no API docs directory, or
the work didn't change the API (params, responses, routes, access rules).
There are two documents, kept apart on purpose:

1. **The change doc**, `.claude/work/<slug>/api-changes.md` (drafted by
   `/brainstorm`; write it if the plan has none but the API changed). A
   hand-over for clients describing this change. Local, **never committed**.
2. **The endpoint docs**, one per endpoint in the API docs directory from
   `.claude/project.md` (e.g. `docs/api/<endpoint>.md`). Update the doc of
   each endpoint touched so it describes the endpoint as it now is; create
   the directory and the doc if they don't exist yet. These are committed,
   last, as `docs(api):`. Don't link the change doc from them.

Check both against what was built: router, controllers, JSON views, and the
API spec schemas (if `.claude/project.md` lists an API spec). Make them match
the code. The change doc covers, per
endpoint touched: what changed (before → after), params, fields, a response
example taken from a real test response, access rules, errors, and ⚠️ on
breaking changes with what a client must change and when. Report any API
spec gap as a finding for a builder to fix.

## Finish

Run `mix compile --warnings-as-errors` and the full `mix test`. Set `plan.md`
to `Status: implemented`.

**Decisions the builders made that the plan didn't dictate:** test each
against the `domain-modeling` skill's ADR bar (hard to reverse, surprising
without context, a real trade-off — all three). One that passes gets a draft
ADR in `docs/adr/` with `status: proposed`, listed in the review guide for
the user to review. The rest go to `docs/MEMORY.md` as dated entries.

**Update the living docs** so they describe what was built, before the user
reviews (they review these changes with the code):

- **`CONTEXT.md`** (the ubiquitous language), with the `domain-modeling`
  skill's format: add terms the built code introduced, sharpen terms whose
  meaning changed, and check that names in the code (modules, schemas,
  fields, status values) use the glossary's words. A mismatch between code
  and glossary is a review-guide finding, not something to rename silently.
- **The architecture doc** (path in `.claude/project.md`), following
  *Architecture doc* in `.claude/commands/document.md`: update only the
  sections the work touched (a new context, schema, route, worker, external
  client), and link any ADR the plan produced. If it doesn't exist yet,
  create it.

If the work changed neither, say so in the review guide and skip. These
changes go in the split as one `docs:` commit after the task commits. The
`CONTEXT.md` terms `/brainstorm` wrote belong to the ADR commit instead, so
if `CONTEXT.md` has both, split it by hunk.

Write a **review guide** to `.claude/work/<slug>/review.md` and show it to
the user, one block per task:
- the task and its planned commit message: what it does, in one line;
- the files to look at, most important first, with `file:line` for the key change;
- decisions the builder made on its own, and review rounds that failed and why;
- how to try it: the test command, and an example request for endpoints.

Then the **proposed commit split**, following the `git` skill: the commits
in order (the plan's ADRs and the `CONTEXT.md` terms `/brainstorm` wrote
first, then one per task, then the living-docs update with the terms added
here, the endpoint docs last), each with
its message and exact files (hunks where a file is shared between tasks).
Write it into `plan.md` under `## Commit split` as well. Both survive a new
session: if the user comes back later to review, read `review.md` and the
split from the task folder instead of rebuilding them.

Then, **if the Redline tools are available** (the Redline VS Code extension
and its Claude Code plugin; check for `redline_ping`), open the Redline
review. Otherwise skip to the closing line and the user reviews `git diff`:

1. Call the `request_review` tool with `source: {kind: "worktree", scope: "all"}`,
   a `title` naming the plan, and `notes` that follow the review guide: one
   per task, in plan order, on the task's key change (`file`, `line`), with a
   `body` whose first line is what the task does, then its planned commit
   message and the decisions the builder made. This opens the uncommitted
   diff in VS Code as a PR-style round. (Don't use `/redline:redline-tour`:
   only the user can invoke it.) The round also shows unrelated changes that
   were in the tree before the work; mention them in the closing line.
2. Load the `redline:redline-connect` skill (with `listen` if `redline_ping`
   reports `monitor: absent`, as in the VS Code chat panel) so submitted
   comments reach you.

End with anything still red and:
`Nothing is committed. Review in the Redline round in VS Code (hover a line, click +, then Submit review) or ask for fixes here. Tell me when you're done reviewing.`
Without Redline, say `Review the working tree (git diff)` instead of the Redline part.

## After review

The user reviews at the end, then tells you they're done (or says "accept").
Don't commit on that alone. First:

1. Fold every fix made during review into the `## Commit split` in
   `plan.md` (each into its task's commit) and run `mix test` once more.
2. Ask in one question (AskUserQuestion): **"Is this reviewed? Shall I split
   it into commits?"**, showing the split (messages and files) with options:
   - *Yes, commit as split* (recommended);
   - *Yes, as one commit* (one message summarising the plan);
   - *Not yet* (more review or fixes; ask again when they say they're done).
3. On a yes, load the `git` skill and commit following *3. Commit* and
   *4. Hand off* in `.claude/commands/commit.md`: stage each commit's files
   or hunks, check the staged set, commit with its message, stop on a failed
   hook, never push. Set `plan.md` to `Status: committed` with the hashes.

   Before the first commit, set the `proposed` ADRs from *Finish* to
   `status: accepted`, and mark any ADR they supersede as
   `superseded by ADR-NNNN`. Those edits go in the ADR commit, with the
   plan's ADRs (already `accepted` by `/brainstorm`). If the user
   rejected a proposed ADR during review, delete it and record the rejection
   in `docs/MEMORY.md`.

## Review comments

This section applies only with Redline. Without it, the user asks for fixes in
the chat; they go through the same builder → reviewer loop.

Submitted Redline threads arrive as one markdown document. Work through them
in file order:

1. A question gets an answer with `reply_comment`; the thread stays open.
2. A requested change goes through the same builder → reviewer loop as any
   other fix, scoped to that task. Then close the thread with
   `resolve_comment` and a one-line note naming what changed (`file:line`).
   A change you decline is resolved with the reason. A proposal that needs
   the user's decision is a `reply_comment`, left open.
3. Never edit or delete the user's comments.

When the batch is done, call `request_review` on the same source (`all`) so
the round refreshes with the fixes. Fixes stay uncommitted.

## Rules

- Sequential, in plan order. Use the Agent tool (subagents), not Agent Teams.
- Builder owns code, reviewer owns the gate, you own sequencing, the commit
  split and, after the user's yes, the commits.
- Fixes asked for after hand-off go through the same builder → reviewer
  loop and stay uncommitted, folded into their task's planned commit.
- Never commit before the user answers yes to "Is this reviewed? Shall I split it into commits?"; "go" or running `/implement` is not acceptance.
- Never migrate or roll back the dev DB. Never push.
- Tests are never skipped. At Finish every test must be green; flaky tests
  listed in `.claude/project.md` may be rerun once.
