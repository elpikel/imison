# User stories

The backlog. There is no issue tracker: pick the first open story whose dependencies are done, run `/brainstorm <ID and story>` to turn it into acceptance criteria and a plan in `.claude/work/<slug>/` (slug: the ID and a short name, e.g. `cap-01-async-capture`), then `/implement`. Tick the box when its commits land on `main`.

Stories come from [`PROJECT.md`](PROJECT.md); "done when" lines summarise what the design there promises and are refined into acceptance criteria by `/brainstorm`. The developer is whoever maintains the host app. Phase 1 is the smallest version worth installing, phase 2 makes it comfortable, phase 3 is extension work. Within a phase, stories are in build order.

IDs: `DEV` setup, `INS` installation, `CAP` capture, `AUTH` auth, `ERR` errors, `NOT` notifications, `MN` multiple nodes.

## Phase 0: setup

These are not in the design's story list; every phase 1 story needs them to be built and tested.

- [x] **DEV-01 Test database for Imison's own tests** · needs: none
  As a maintainer, I want a test repo on Postgres with the SQL sandbox, so that schemas, upserts and migrations are tested against a real database.
  Done when: `mix test` creates and migrates a test database through `Imison.Migration` and runs tests in the sandbox.

- [x] **DEV-02 Development host app** · needs: DEV-01
  As a maintainer, I want a small Phoenix app under `dev/` that hosts Imison and can raise sample errors, so that I can see Imison working the way a host app runs it.
  Done when: one command starts the app, a page or task raises sample errors, and `dev/` is excluded from the Hex package.

## Phase 1: smallest version worth installing

### Core and capture

- [x] **INS-05 Refuse to start on bad config** · needs: none
  As a developer, I want Imison to refuse to start with a clear message when a required option is missing, so that a bad config shows up at boot.
  Done when: `{Imison, opts}` without `repo`, `username` or `password` fails to start with a message naming the missing option; unknown options are rejected too.

- [x] **INS-02 Tables through an Ecto migration** · needs: DEV-01
  As a developer, I want the tables created by a normal Ecto migration in my repo, so that they deploy and roll back with the rest of my schema.
  Done when: `Imison.Migration.up(version: 1)` creates the six `imison_` tables with the unique index on `fingerprint`, and `down(version: 1)` removes them.

- [x] **ERR-01 Group identical errors** · needs: INS-02
  As a developer, I want identical errors grouped into one row with a count, so that one bug does not flood the list.
  Done when: two occurrences with the same exception module and first application frame but different messages produce one error with `occurrence_count` 2 and two occurrences, written in one transaction that also increments the hourly count.

- [x] **CAP-04 Asynchronous capture that drops under load** · needs: ERR-01, INS-05
  As a developer, I want capture to be asynchronous and to drop events under load, so that the tracker can never slow or crash my app.
  Done when: handlers only build the event and cast it to the worker; with the worker's queue full, events are dropped and counted; an error inside Imison is logged, never captured.

- [x] **CAP-01 Capture without code changes** · needs: CAP-04
  As a developer, I want crashes, Phoenix request errors and Oban job failures captured with no changes to my code, so that setup stays trivial.
  Done when: a crashed process, a raising Phoenix request and a failing Oban job each produce an occurrence; the Oban hook attaches only when Oban is loaded; modules in `ignore` are never recorded.
  Note: the Oban handler attaches unconditionally, not only when Oban is loaded: a telemetry handler for an event nobody emits never fires, so it is harmless when Oban is absent and no code references Oban.

- [x] **CAP-02 Report rescued exceptions** · needs: CAP-04
  As a developer, I want to report a rescued exception myself with `Imison.report/3`, so that handled errors are tracked too.
  Done when: `Imison.report(exception, stacktrace, metadata)` records an occurrence with that metadata in its context.

- [x] **CAP-03 Filter sensitive data** · needs: CAP-01
  As a developer, I want sensitive params and headers filtered before storage, so that passwords and tokens never reach the database.
  Done when: keys from `filter` (default `password`, `token`, `secret`, `authorization`, `cookie`), at any depth in params, headers and metadata, are stored as `[FILTERED]`.

- [ ] **INS-06 Capture off in tests** · needs: CAP-01
  As a developer, I want capture switched off in tests, so that expected failures do not fill the database.
  Done when: with `enabled: false`, no handlers are attached and `report/3` writes nothing.

- [ ] **ERR-09 Reopen on regression** · needs: ERR-01
  As a developer, I want a resolved error to reopen when it happens again, so that regressions are not hidden.
  Done when: a new occurrence of a `resolved` error sets it to `unresolved` and flags it as a regression; `ignored` errors stay ignored.

- [x] **MN-01 One error list for all nodes** · needs: ERR-01
  As a developer running several nodes, I want every node to feed one error list, so that I do not check each node separately.
  Done when: concurrent upserts of the same fingerprint from separate processes produce one error with the summed count and no lost increments.
  Delivered with ERR-01: errors are upserted with SQL-side increments.

- [ ] **MN-03 Node of each occurrence** · needs: ERR-01
  As a developer, I want to see which node each occurrence came from, so that I can spot a single bad instance.
  Done when: each occurrence stores the node name in its runtime context.

### Dashboard and auth

- [ ] **INS-03 Mount the dashboard with one macro** · needs: DEV-02
  As a developer, I want the dashboard mounted with one router macro at a path I choose, so that it is part of my app and not another service.
  Done when: `imison_dashboard "/errors"` inside a `:browser` scope serves the dashboard and Imison's own `app.css` and fonts from `priv/static`, with no change to the host's asset pipeline.

- [ ] **AUTH-01 Login from environment variables** · needs: INS-03, INS-05
  As a developer, I want to set the dashboard username and password in environment variables, so that there is no account setup step.
  Done when: the credentials come only from config (set from `IMISON_USER` and `IMISON_PASSWORD`) and are compared with `Plug.Crypto.secure_compare/2`.

- [ ] **AUTH-02 Sign in, stay signed in, sign out** · needs: AUTH-01
  As a developer, I want to sign in once and stay signed in, and to sign out, so that the dashboard is private but not annoying.
  Done when: every dashboard route except login redirects to login without a session; a correct login sets a signed session cookie valid on every node; sign out clears it. Screen: `docs/design/login.html`.

- [ ] **ERR-02 Filter by status and search** · needs: AUTH-02, ERR-01
  As a developer, I want to filter the list by status and to search by text, so that I can find what matters.
  Done when: tabs for unresolved, resolved and ignored show their counts, and search matches kind, message and location. Screen: `docs/design/errors.html`.

- [ ] **ERR-03 24-hour heat strip** · needs: ERR-02
  As a developer, I want to see how often each error happened over the last 24 hours, so that I can tell a spike from background noise.
  Done when: each row shows 24 hourly cells from `imison_hourly_counts`, coloured on the heat scale.

- [ ] **ERR-04 Live list** · needs: ERR-02
  As a developer, I want the list to update live as errors happen, so that I can watch a deploy.
  Done when: a new or repeated occurrence broadcast on the host PubSub updates rows, counts and heat strips in an open list without a reload.

- [ ] **ERR-05 Error detail** · needs: ERR-02
  As a developer, I want to open an error and see the message, stack trace, request, metadata and runtime, so that I can reproduce it.
  Done when: the detail page shows the latest occurrence's stack trace and its request, metadata and runtime context (incl. node and release). Screen: `docs/design/error-detail.html`.

- [ ] **ERR-06 Application frames first** · needs: ERR-05
  As a developer, I want my application's frames distinguished from dependency frames, so that I find my code first.
  Done when: frames from the host app's own modules are styled as application frames and dependency frames are muted.

- [ ] **ERR-08 Resolve and ignore** · needs: ERR-02
  As a developer, I want to resolve or ignore errors, one at a time or in bulk, so that the unresolved list stays a to-do list.
  Done when: from the detail page and from a multi-select on the list, errors move to `resolved` or `ignored` and back to `unresolved`.

### Notifications

- [ ] **NOT-01 Email on a new error** · needs: ERR-01, INS-05
  As a developer, I want an email through my app's existing mailer when a new error appears, so that I hear about it without watching the dashboard.
  Done when: a new error sends one email through the host's Swoosh mailer from `from` to the configured recipients, with a link to the error; the email channel compiles only when Swoosh is present; the `Channel` behaviour exists.

- [ ] **MN-02 One notification per event across nodes** · needs: NOT-01, ERR-09
  As a developer, I want one notification per event even when several nodes catch the same error at the same moment, so that alerts are not duplicated.
  Done when: only the process whose upsert inserted the error sends "new", and only the one whose `UPDATE ... WHERE status = 'resolved'` changed the row sends "regression", even under concurrent capture.

- [ ] **NOT-02 Email when a resolved error comes back** · needs: MN-02
  As a developer, I want an email when a resolved error comes back, so that I know a fix did not hold.
  Done when: a regression sends one email marked as a returning error.

- [ ] **NOT-03 Send a test email** · needs: NOT-01, AUTH-02
  As a developer, I want to send a test email, so that I know delivery works before I rely on it.
  Done when: the Notifications screen sets recipients and enables rules, and a "send test" action delivers or shows the mailer's error. Screen: `docs/design/notifications.html`.

### Installation

- [ ] **INS-01 One install task** · needs: INS-02, INS-03, AUTH-01
  As a developer, I want to add one dependency and run `mix imison.install`, so that config, supervision, migration and route are set up without hand edits.
  Done when: on a fresh `mix phx.new` app the Igniter task makes the five changes from `PROJECT.md` plus `enabled: false` in `config/test.exs`, skips changes already present, and the app boots and shows the dashboard after `mix ecto.migrate`.

- [ ] **INS-04 Manual install steps** · needs: INS-01
  As a developer, I want the manual steps documented, so that I can install without Igniter.
  Done when: the README lists each step by hand, and without Igniter `mix imison.install` prints them.

## Phase 2: comfortable

- [x] **INS-07 Versioned migrations** · needs: INS-02
  As a developer, I want schema changes in later versions delivered as numbered migration versions, so that upgrading is one new migration.
  Done when: `up(version: n)` applies only versions not yet applied, `down` reverses them, and a version only adds tables, columns and indexes.
  Delivered with INS-02: `Imison.Migration` tracks the applied version from version 1.

- [ ] **CAP-05 Retention** · needs: ERR-01
  As a developer, I want old occurrences deleted after a retention period, so that the tables stay small.
  Done when: a pruner deletes occurrences older than `retention_days` (default 30) and keeps the error row; running it on several nodes is safe.

- [ ] **AUTH-03 Slow down failed logins** · needs: AUTH-02
  As a developer, I want repeated failed logins slowed down, so that the password cannot be brute-forced.
  Done when: failed attempts are counted in the database and each further attempt is delayed, across nodes.

- [ ] **ERR-07 Step through occurrences** · needs: ERR-05
  As a developer, I want to step through individual occurrences, so that I can compare what differed between them.
  Done when: the detail page moves to the previous and next occurrence of the error.

- [ ] **MN-04 Live updates without clustering** · needs: ERR-04
  As a developer, I want the dashboard to stay current when my nodes are not clustered, so that live updates do not depend on distributed Erlang.
  Done when: without `pubsub`, or without connected nodes, an open list refreshes from the database every few seconds.

- [ ] **NOT-04 Throttle repeat notifications** · needs: MN-02
  As a developer, I want repeat notifications for the same error throttled, so that an outage does not send hundreds of emails.
  Done when: "still happening" notifications for one error are sent at most once per period, recorded in `imison_deliveries`.

- [ ] **MN-05 Reminders and digest sent once** · needs: NOT-04
  As a developer, I want reminders and the daily digest sent once, not once per node, so that scaling out does not multiply my email.
  Done when: a node sends only after its insert into `imison_deliveries` under the unique (error, trigger, period) index succeeds.

- [ ] **NOT-05 Mute an error** · needs: NOT-01
  As a developer, I want to mute a single error, so that a known issue stops notifying while it stays visible.
  Done when: a muted error sends no notifications and still appears and counts in the list.

- [ ] **NOT-06 Daily digest** · needs: MN-05
  As a developer, I want a daily digest, so that I get a summary instead of single alerts.
  Done when: with the digest rule on, one email a day summarises the day's new, returning and most frequent errors.

## Phase 3: extensions

- [ ] **NOT-07 More channels and custom channels** · needs: NOT-01
  As a developer, I want to add Slack, a webhook or Telegram as a channel, or write my own channel module, so that alerts reach me where I already look.
  Done when: a host module implementing `Imison.Notifications.Channel` and listed in `channels` receives messages; Slack and webhook channels ship with Imison.
