# 🧰 Claude workflow kit (Elixir/Phoenix)

How to take an issue or an idea to reviewed, accepted, committed code with the slash commands, agents and skills in this folder. Built for Elixir/Phoenix, Ecto/PostgreSQL and ExUnit; Oban, LiveView, ExMachina, Mox, Credo and OpenApiSpex are used when the project has them.

The kit is generic. Everything specific to a repo (trunk branch, issue tracker, databases, tooling, test layout, router pipelines, access rules, style overrides) lives in **`.claude/project.md`**, which the commands and agents read. `/init` writes it from **`project.template.md`**.

---

## 🚀 Using the kit in a repo (new or ongoing)

**You need** an up-to-date Claude Code (`claude update`): the kit relies on project subagents in `.claude/agents/` that use the `Skill` tool, on `AskUserQuestion`, and on the built-in `Explore` and `general-purpose` subagents. Older versions may lack one of these.

1. Copy these from this repo into the other repo's `.claude/`:
   - `commands/`
   - `agents/`
   - `skills/`
   - `README.md`
   - `project.template.md`

   Don't copy `project.md`, `settings.local.json` or `work/`; they belong to one repo or one person. If the repo already has a `.claude/` folder, the kit's files sit alongside yours; rename any command, agent or skill of yours that clashes: commands `init`, `brainstorm`, `implement`, `commit`, `document`; agents `builder`, `reviewer`; skills `git`, `bdd-specs`, `domain-modeling`, `design-principles`, `postgres-dba`. Check your personal `~/.claude/skills/` too: a personal skill with the same name wins over the repo's copy, so the kit would silently use yours (e.g. a generic `domain-modeling` without the kit's ADR status rules).
2. Run `/init`. It works on a fresh `mix phx.new` app and on an existing codebase:
   - **Checks** it's an Elixir/Phoenix repo, and for an existing codebase **explores** it first (contexts, schemas, routes, workers, external clients).
   - **Detects** the app, databases, table prefixes, router pipelines, test cases and layout, and the tools in use (Credo, Styler, Oban, ExMachina or fixtures, Mox, OpenApiSpex, LiveView). Tools the repo doesn't use are marked "none", and the agents never run or require them.
   - **Asks** only what it can't detect: the issue tracker (or local tasks), whether `/implement` may run on the trunk, the trunk if unclear, access rules, style overrides, seeded data tests must never delete, flaky tests, the canonical word where the code mixes synonyms, and (for a new repo) what the app is for.
   - **Writes** `.claude/project.md`, the `README.md` (replacing `phx.new` boilerplate) and `ARCHITECTURE.md` (a short skeleton for a new repo, a full map for an existing one; ones a person wrote are only checked for drift), a "Work tracking" section in `CLAUDE.md` (plus an `@AGENTS.md` import when Phoenix 1.8's `AGENTS.md` exists, since Claude Code doesn't read that file on its own), `CONTEXT.md` (the ubiquitous language: terms taken from the code for an existing repo, asking which word is canonical where the code mixes synonyms), any missing `docs/adr/` and `docs/MEMORY.md`, and adds `.claude/work/` and `.claude/settings.local.json` to `.gitignore`. It never overwrites a file a person wrote, so it's safe to re-run.
3. Optionally, allow the commands the agents run so you aren't asked for each one. Add to `.claude/settings.json` (committed, shared with the team) or your own `.claude/settings.local.json`:

   ```json
   {
     "permissions": {
       "allow": [
         "Bash(mix format:*)", "Bash(mix compile:*)", "Bash(mix test:*)",
         "Bash(mix credo:*)", "Bash(mix ecto.gen.migration:*)",
         "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)",
         "Bash(git add:*)", "Bash(git apply --cached:*)",
         "Bash(git restore --staged:*)", "Bash(git commit:*)"
       ]
     }
   }
   ```

   Leave out `git commit` if you want Claude Code to prompt for each commit as well; the flow already asks before committing.
4. Review `.claude/project.md`, commit the kit, and start with `/brainstorm`.

Teammates on a repo that already has the kit committed need no setup.

### Updating the kit in a repo

Replace `commands/`, `agents/` and `skills/` with the new ones (delete the old folders first, so files the kit dropped don't linger), and copy `README.md` and `project.template.md` over. `project.md` isn't part of the copy, so repo settings survive. If the new `project.template.md` has rows your `project.md` lacks, re-run `/init`: it fills only the missing rows.

---

## 🗺️ The flow

```
💡 issue (pasted) or an idea
  │
/brainstorm <paste>     talk it through, then write the plan and its docs:
  │                     plan, acceptance criteria (+ stories), ADR and API change doc if needed
  ✋ you review the docs, ask for changes
/implement              builder writes tests + code, reviewer gates,
  │                     nothing committed
  ✋ you review in Redline (or the working tree), comments go back to the agent
  ❓ "Is this reviewed? Shall I split it into commits?"
yes                     commits the planned split: one per task, proper messages
```

| Size of the change | What to run |
|---|---|
| 🐜 Typo, wrong condition, stale doc line | Just ask in the chat |
| 🧩 A feature or behaviour change | `/brainstorm` → review → `/implement` → review → "yes, commit" |
| 💾 Changes made outside the flow | `/commit`: it derives a split from the tree and asks before committing (a pending `/implement` split is committed without asking again) |
| 📝 Docs drifted from the code | `/document` |

**Before `/implement`, create your feature branch from the trunk**, unless `.claude/project.md` allows work on the trunk. Claude never switches branches, and otherwise `/implement` refuses to run on the trunk.

---

## 1. `/brainstorm <pasted issue or idea>`

Paste the issue description, or describe the idea. Claude reads the code it touches, the related ADRs and API docs, and talks it through with you:
- restates the task with what the code does today;
- points out conflicts with existing behaviour, ADRs or the access rules, and anything ambiguous in the task;
- asks what the code can't answer and recommends options;
- keeps a list of what's agreed and what's still open.

Nothing is written until you say yes to "Write the plan?". Then:

| Doc | Where | When |
|---|---|---|
| `plan.md` | `.claude/work/<slug>/` | Always: the approach, then tasks in order, each with its files, criteria and commit message. |
| `stories.md` | `.claude/work/<slug>/` | Always: acceptance criteria as Given/When/Then; a user story on top when it helps. |
| ADR | `docs/adr/NNNN-<slug>.md` | Only for a decision that's hard to reverse, surprising and a real trade-off. Written `accepted`: you agreed it in the conversation. |
| API change doc | `.claude/work/<slug>/api-changes.md` | Only if the API changes: the contract for API clients, before → after, drafted up front. Local. |
| Terms | `CONTEXT.md` | Only new domain terms (the ubiquitous language). `/implement` reconciles them with what was built. |

`.claude/work/` is gitignored: the plan and stories are working docs for you and `/implement`. With an issue tracker, the tracker stays the record and the slug starts with the issue id, e.g. `abc-123-member-prices`. With local tasks (set in `.claude/project.md`), `.claude/work/<slug>/` is the record and the slug is a short name, e.g. `member-prices`.

Review the docs and ask for changes in the same chat. Rerunning `/brainstorm` on the same slug refines them.

## 2. `/implement [slug]`

Running it is your sign-off on the plan. For each task in `plan.md`:
1. The **builder** (Opus) writes the task's tests from its acceptance criteria (red), then the code, and runs format, compile, the linter (if the repo has one) and tests.
2. The **reviewer** (Opus) checks the diff against the task, its criteria, the project rules, the access rules and security: PASS or FAIL.
3. On FAIL, a fresh builder fixes the findings and the reviewer checks again, until it passes.
4. Wire tasks are smoke-tested through the real entry point: the router, the LiveView, or the worker's `perform/1`.
5. The task's files are recorded and the task is ticked. Nothing is staged or committed.

If a run is interrupted (a crash, a closed session), run `/implement` again: a plan left at `Status: implementing` resumes from its first unticked task.

Docs-only tasks (the task owns only Markdown) are written by the builder and checked by the reviewer against the criteria, without tests. If they state facts about third-party services, a research agent with web access gathers sourced notes first, since the builder and reviewer have none.

When all tasks pass:
- **API docs:** if the API changed, the API change doc is checked against the built code and API spec, and the docs of the endpoints touched are updated.
- **Unplanned decisions:** any the builder made that meet the ADR bar get a `proposed` ADR for you to review; the rest go to `docs/MEMORY.md`.
- **Living docs:** `CONTEXT.md` and `ARCHITECTURE.md` are brought in line with what was built, so you review them with the code.
- The full suite runs once more.

## 3. Review

`/implement` ends with a **review guide** (also saved as `.claude/work/<slug>/review.md`, so you can review in a later session), one block per task: what it does, the files to look at (`file:line`), decisions the builder made on its own, failed review rounds, and how to try it. Then a **proposed commit split**:
1. `docs:` the ADRs, if any: the plan's, plus any unplanned ones you accepted in review (older ones they supersede marked), with the `CONTEXT.md` terms `/brainstorm` wrote;
2. one commit per task (shared files split by hunk);
3. `docs:` the `ARCHITECTURE.md` update and the `CONTEXT.md` terms added while building, if any (a `CONTEXT.md` changed in both places is split by hunk);
4. `docs(api):` the endpoint docs, if the API changed.

The split is also written to `plan.md` under `## Commit split` (each commit's message and files or hunks, in order). `/commit` reads that section, so if you edit `plan.md` by hand, keep it in that shape.

If you have Redline installed, it then opens a **Redline review** in VS Code: the uncommitted diff as a PR-style round, with one note per task. Hover a line, click **+** to comment, then **Submit review**. Claude fixes each thread through the same builder → reviewer loop, then resolves it or replies, and refreshes the round. You need the [Redline](https://nikiforovall.blog/redline/guide) VS Code extension and its plugin (`/plugin marketplace add nikiforovall/redline`, then `/plugin install redline@redline`). If you run Claude in the VS Code panel rather than a terminal, run `/redline:redline-connect listen` so comments reach the session.

Without Redline (it's optional), review the working tree (`git diff`) and ask for fixes in the chat. Either way, fixes stay uncommitted.

## 4. Commit

When you're done reviewing, say so. Claude folds the review fixes into the split and asks **"Is this reviewed? Shall I split it into commits?"**: commit as split, as one commit, or not yet. On a yes it commits the split from `plan.md`, in order, with Conventional Commit messages (the `git` skill) and the commit reference from `.claude/project.md`, if any, staging shared files hunk by hunk.

**Pausing:** answering *Not yet* leaves the plan at `Status: implemented` with its split in `plan.md`, and `review.md` keeps the guide. Come back in any session, run `/implement` (it sees the plan is built and goes straight to the question), and Claude asks again. Note that a plain `/commit` run while that plan is pending commits its split straight away, without asking: running it counts as your yes.

For changes made outside the flow, run `/commit`: it derives a split from the tree, shows it, and asks before committing. Either way, attribution lines follow your own rules, nothing is pushed, amended or rebased, and unrelated changes in your tree are left alone. Then push and open the PR yourself.

---

## 🧪 Test rules (enforced by the agents)

- **Never skipped.** No `@tag :skip` and no exclusion tags. Every commit leaves the suite green.
- **Where tests live:** endpoint tests in one file per controller action (`<controller>/<action>_test.exs`), module tests mirroring `lib/`. The exact paths and test cases are in `.claude/project.md`. Files are never named after stories or issues.
- **Shape:** flat top-level `test` blocks named by behaviour. No `describe`, no `setup`. Each test arranges its own data (factory or fixtures, whichever the repo uses). External APIs never hit the network (Mox, or the repo's seam).
- **Defaults, not dogma:** these and the Elixir conventions in `agents/builder.md` are the kit's defaults. Turn any off for a repo under *Style overrides* in `.claude/project.md`.

---

## 🤖 Agents

| Agent | Model | Role |
|---|---|---|
| `builder` | Opus | Implements one task, tests first. Follows the Elixir conventions in `agents/builder.md`. Never commits, never switches branches, never migrates the dev DB. |
| `reviewer` | Opus | Read-only gate. Runs the checks itself, traces the entry point, and fails on rule violations, access-rule breaches, security issues or dead code. |

`/implement` coordinates them (Sonnet), updates the living docs, proposes the commit split and, after your review and yes, makes the commits. It never writes or reviews code itself.

## 🧭 Commands

| Command | Model | Use it to |
|---|---|---|
| `/init` | Sonnet | Set the kit up in a repo, new or ongoing. Safe to re-run. |
| `/brainstorm <paste>` | Opus | Talk a task through; write the plan, criteria, and ADR/API change doc if needed. |
| `/implement [slug]` | Sonnet | Build the plan with builder + reviewer, uncommitted; after your review, ask and commit the planned split. |
| `/commit [slug]` | Sonnet | Commit changes made outside the flow as small commits with proper messages. Asks first, except for a pending `/implement` split it commits as planned. Never pushes. |
| `/document [area]` | Sonnet | Bring README, `ARCHITECTURE.md`, `CONTEXT.md` and `MEMORY.md` back in line with the code. Defines what README and `ARCHITECTURE.md` contain. |

## 📚 Skills

| Skill | Used for |
|---|---|
| `bdd-specs` | The builder writing a task's tests from its acceptance criteria. |
| `domain-modeling` | ADRs and the ubiquitous language in `CONTEXT.md`: built by `/init`, extended by `/brainstorm`, reconciled with the code by `/implement` and `/document`. |
| `design-principles` | Module and context design in Elixir: coupling, cohesion, seams. |
| `postgres-dba` | Ecto migrations, schemas, indexes, views. |
| `git` | Splitting changes into commits, Conventional Commit messages, staging single hunks (`/commit`, commit messages in `/brainstorm` plans). |

---

## ⚠️ Things to know

- **Nothing is committed until you say yes** to "Is this reviewed? Shall I split it into commits?" (or run `/commit`). Nothing is pushed, ever.
- **Claude never writes to the issue tracker.**
- **The dev DB is never migrated or rolled back.** Migrations are verified on the test DB (`mix test` migrates it).
- **Known flaky tests** are listed in `.claude/project.md`. Rerun before investigating.
