---
description: Commit uncommitted changes as a clean series of commits with proper Conventional Commit messages — for work done outside /implement (which commits itself after your review), or a plan's split if one is pending. Never pushes.
argument-hint: [feature slug, optional]
model: sonnet
---

# commit

Turn uncommitted work into a series of small, well-described commits. Use it
for changes made outside the flow; `/implement` asks and commits its own work
after your review, using the same steps. Load
the `git` skill first: it holds the splitting rules, the message format and
how to stage single hunks. Repo facts are in `.claude/project.md`.

Running `/commit` is the user's acceptance of the work. It commits locally
and never pushes.

## 1. Preflight

1. Read `.claude/project.md`. If the current branch is the trunk and it
   doesn't say *Work on trunk: Allowed*, stop:
   `You're on <trunk>. Create a feature branch first, or allow work on the trunk in .claude/project.md.`
2. Stop if a merge, rebase or cherry-pick is in progress, or if there's
   nothing to commit (`git status --porcelain` is empty).
3. If something is already staged, note it: the split below decides what goes
   where, so unstage it first (`git restore --staged -- <files>`), keeping the
   changes in the working tree.

## 2. The split

Take the first that applies:

1. **A plan.** `.claude/work/<slug>/plan.md` from `$ARGUMENTS`, else the only
   plan with `Status: implemented`. Use its `## Commit split` section, written
   by `/implement`: the commits in order, each with its message and exact
   files or hunks.
   Check it against the tree: every changed file must belong to exactly one
   commit or be listed as left out. If the tree has changes the split doesn't
   cover (e.g. fixes after review), assign them to the commit of the task they
   belong to; if they belong to none, propose an extra commit.
2. **No plan.** Read `git status` and `git diff` (and new files in full) and
   derive the split with the `git` skill's rules. Write each message from the
   change itself and the conversation; never invent a reason you don't know.
   If the reason is unclear, ask.

Show the split as a numbered list: message (subject, plus body if any) and
files, marking hunk-split files with which hunks go where. List what is left
out and why.

- From an unchanged plan split: commit straight away. The user saw that
  split in `/implement`'s review guide, and running `/commit` accepts it.
- Derived, or a plan split you had to change: ask once, "Commit as above?",
  and wait.

## 3. Commit

For each commit, in order:

1. Stage exactly its files or hunks (see *Staging* in the `git` skill).
2. Check `git diff --cached --stat` lists only them.
3. `git commit -F -` with the message. Add the commit reference from
   `.claude/project.md` if any, and attribution lines only as the user's
   rules ask.
4. If a hook fails, stop and report its output. Don't bypass it and don't
   commit the rest.

## 4. Hand off

Show `git log --oneline -<n>` for the new commits and `git status --short` for
what's left (with why it was left out). If a plan was used, set it to
`Status: committed` and list the hashes under `## Commit split`.

End with: `Committed locally. Nothing is pushed.`
