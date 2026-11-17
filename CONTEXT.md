# Imison

An error tracker that runs inside a Phoenix app: it captures the app's errors, groups them, stores them in the app's own database and shows them on a dashboard mounted in the app's router.

## Language

### Hosting

**Host app**:
The Phoenix application that depends on Imison and supplies its repo, PubSub, mailer and router.
_Avoid_: client app, parent app, project

**Developer**:
Whoever maintains the host app and uses the dashboard; the only kind of user Imison has.
_Avoid_: user, admin, customer

**Dashboard**:
Imison's LiveView screens, mounted in the host app's router with `imison_dashboard`.
_Avoid_: admin panel, UI, web console

**Overview**:
The dashboard's landing page: a glimpse of errors and of analytics, each linking to its full page.
_Avoid_: home, summary, dashboard (the whole set of screens)

### Errors

**Error**:
A group of occurrences with the same fingerprint; one row in the error list.
_Avoid_: issue, exception group, incident

**Occurrence**:
One captured event belonging to an error, with its stack trace, context, release and node.
_Avoid_: event, instance, hit

**Fingerprint**:
The hash that decides which error an occurrence belongs to: the exception module plus the first application frame (or the first frame when there is none), never the message.
_Avoid_: group key, signature

**Kind**:
The exception module (or `exit`/`throw`) of an error.
_Avoid_: type, class

**Application frame**:
A stack frame from the host app's own code, as opposed to a dependency frame: its module belongs to the OTP app of the host repo Imison is configured with.
_Avoid_: in-app frame, user frame

**Location**:
Where an error happened: the first application frame as `Module.function/arity (file:line)`, or the first frame when no frame is an application frame; none when the stack trace is empty.
_Avoid_: origin, source

**Status**:
Where an error stands: `unresolved`, `resolved` or `ignored`.
_Avoid_: state

**Regression**:
A resolved error that receives a new occurrence and returns to `unresolved`.
_Avoid_: reopen, recurrence

**Muted**:
A flag on an error, separate from its status, that stops the notifications about that error (new, regression, still happening) while it stays listed and counted under its status. The daily digest, a summary, still lists muted errors.
_Avoid_: snoozed, silenced

**Hourly count**:
The number of occurrences of one error in one hour; feeds the heat strip.
_Avoid_: bucket, histogram

**Retention**:
How many days occurrences are kept before the pruner deletes them; errors themselves are kept.
_Avoid_: TTL, expiry

### Notifications

**Channel**:
A configured way of delivering notifications (email first), implemented by a module with the `Imison.Notifications.Channel` behaviour and listed in the `channels` option; its settings (e.g. the email recipients) are stored once per channel type.
_Avoid_: integration, provider, notifier

**Rule**:
Whether a trigger notifies; a trigger without a stored rule notifies for `new` and `regression` only.
_Avoid_: alert, policy

**Trigger**:
What a rule fires on: `new`, `regression`, `still_happening` or `digest`.
_Avoid_: event, condition

**Message**:
The channel-neutral content of one notification: trigger, kind, message, location, counts and a link to the error.
_Avoid_: alert, payload

**Delivery**:
A record of one notification sent, or failed, through one channel, used for throttling and debugging.
_Avoid_: notification log, send

**Digest**:
A daily summary of errors sent instead of single notifications.
_Avoid_: report, summary email

### Analytics

**Pageview**:
One page shown to a visitor: a full page load of an HTML page, or a LiveView `navigate` or `patch` to a new path; stored as one row in `imison_pageviews`.
_Avoid_: hit, visit, page load

**Visitor**:
Who viewed a page, identified only by a hash of the day's salt, the IP and the user agent; the same person counts as a new visitor each UTC day, and no IP, user agent or cookie is stored.
_Avoid_: user, session, client

**Daily salt**:
The random value mixed into the visitor hash for one UTC day, stored in the database so every node computes the same visitor; kept for today and yesterday only, so visitors can't be linked across days.
_Avoid_: key, secret

**Visit**:
A visitor's pageviews with no gap longer than 30 minutes. Within a range, a visit that started before the range counts only from its first pageview inside it, and a visit crossing midnight UTC splits in two, because the visitor changes with the day.
_Avoid_: session

**Visit duration**:
The time from a visit's first pageview to its last; the time spent on the last page is unknown and counts as zero, so a bounce lasts zero seconds.
_Avoid_: session length, time on site

**Bounce**:
A visit with a single pageview.
_Avoid_: exit

**Range**:
The span the analytics are shown for: today, the last 7 days or the last 30 days, in whole UTC days ending now.
_Avoid_: timeframe, window

**Source**:
Where a pageview came from: the referrer's host without `www.`, or none (shown as "Direct / None") when there is no referrer or it's the app's own host.
_Avoid_: referrer, channel (a notification term)
