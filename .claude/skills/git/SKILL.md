---
name: git
description: Git conventions for this kit — splitting a working tree into small, reviewable commits, writing Conventional Commit messages, and staging whole files or single hunks without interactive git. Use when committing (the /commit command loads it), when planning a commit split for a /brainstorm plan, or when the user asks how to split or word commits.
---

# Git

Repo facts (trunk, whether work on the trunk is allowed, commit reference
format) are in `.claude/project.md`. The user's own rules (CLAUDE.md, memory)
on attribution lines win over anything here.

## Splitting: one reason per commit

A good commit can be reviewed, reverted and bisected on its own.

1. **One concern per commit.** A feature task, a bug fix, a refactor, a
   dependency bump and a formatting sweep are separate commits even when they
   touch the same file.
2. **Each commit stands alone.** It compiles and its tests pass without any
   later commit. Code and its tests go together; a migration goes with the
   schema and code that use it; a new module goes with its first caller.
3. **Order:**
   1. decisions first: ADRs and the `CONTEXT.md` terms agreed with them in
      `/brainstorm` (`docs:`);
   2. preparatory refactors and dependency changes (`refactor:`, `chore(deps):`);
   3. one commit per task, in plan order (`feat:`/`fix:`);
   4. docs that describe the result last: `CONTEXT.md` terms added while
      building and the architecture doc (`docs:`), then endpoint docs
      (`docs(api):`). A `CONTEXT.md` with terms from both is split by hunk.
   Local working docs in `.claude/work/` (plan, stories, review guide, API
   change doc) are never committed.
4. **Shared files are split by hunk**, each hunk going to the commit whose
   task it belongs to. If a hunk serves two tasks, it goes to the earlier one.
5. **Don't split below meaning.** A rename and its call sites are one commit.
   Five commits of one line each are worse than one coherent commit.
6. **Never commit:** secrets (`.env`, keys, tokens), local settings
   (`.claude/settings.local.json`), `.claude/work/`, build output, editor files,
   or unrelated changes that were in the tree before the work started. List
   them and leave them unstaged.

## Messages: Conventional Commits

```
<type>(<scope>): <subject>

<body: what changed and why, wrapped at 72>

<footers>
```

- **type:** `feat` (new behaviour), `fix` (bug), `refactor` (no behaviour
  change), `perf`, `test` (tests only), `docs`, `chore` (deps, tooling),
  `build`, `ci`, `style` (formatting only).
- **scope:** the context or area touched, in the repo's words: `orders`,
  `catalog`, `web`, `deps`, `adr`. Omit it if the commit is truly cross-cutting.
- **subject:** imperative ("add", not "added"/"adds"), lowercase after the
  colon, no trailing period, at most 72 characters including the prefix. Say
  what the change does for the system, not which files moved.
- **body:** optional for a self-evident change. Otherwise explain **why**,
  the behaviour before → after, and any trade-off or rejected alternative.
  Never restate the diff line by line.
- **footers**, one per line:
  - the commit reference from `.claude/project.md` (e.g. `Refs ABC-123`);
    none if tasks are local;
  - `BREAKING CHANGE: <what breaks and how to migrate>` for breaking changes
    (also add `!` after the type/scope: `feat(api)!: …`);
  - attribution lines only as the user's rules ask.

Good:

```
feat(catalog): show member prices only to premium members

Product listings returned member_price to every customer. It now comes
back only when the caller's Membership is premium; everyone else gets
the list price, and a member_price param from them is ignored.

Refs ABC-123
```

Bad: `update files`, `fix stuff`, `WIP`, `feat: added ProductController changes and tests.`

## Staging without interactive git

Interactive flags (`git add -p`, `git add -i`, `git commit` without `-m`/`-F`)
don't work here. Instead:

- **Whole files:** `git add -- <file>…` (new files too). For a deleted file,
  `git rm --cached -- <file>` or `git add -- <file>`.
- **Single hunks of a file:**
  1. `git diff -- <file> > <scratch>/<file>.patch`
  2. Edit the patch to keep only this commit's hunks (delete the other
     `@@` blocks whole; keep the `diff --git`/`---`/`+++` header).
  3. `git apply --cached --recount <scratch>/<file>.patch`
  4. Check with `git diff --cached -- <file>`.
  Put patch files in the session's scratchpad directory, never in the repo.
- **Start each commit from a known index:** `git diff --cached --name-only`
  must list only this commit's files before you commit.
- **Commit with a message file or heredoc:**
  `git commit -F - <<'EOF'` … `EOF` (keeps the body's line breaks).

## Never

- Push, force-push, amend, rebase, reset `--hard`, or `checkout`/`restore`
  files with uncommitted changes (`git restore --staged` is fine: it only
  unstages and leaves the working tree alone).
- Skip hooks (`--no-verify`). If a pre-commit hook fails, stop, report its
  output, and fix through the normal flow.
- Switch or create branches; the user does that.
