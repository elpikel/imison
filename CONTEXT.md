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

### Errors

**Error**:
A group of occurrences with the same fingerprint; one row in the error list.
_Avoid_: issue, exception group, incident

**Occurrence**:
One captured event belonging to an error, with its stack trace, context, release and node.
_Avoid_: event, instance, hit

**Fingerprint**:
The hash that decides which error an occurrence belongs to: the exception module plus the first application frame, never the message.
_Avoid_: group key, signature

**Kind**:
The exception module (or `exit`/`throw`) of an error.
_Avoid_: type, class

**Application frame**:
A stack frame from the host app's own code, as opposed to a dependency frame.
_Avoid_: in-app frame, user frame

**Status**:
Where an error stands: `unresolved`, `resolved` or `ignored`.
_Avoid_: state

**Regression**:
A resolved error that receives a new occurrence and returns to `unresolved`.
_Avoid_: reopen, recurrence

**Muted**:
A flag on an error that stops notifications while it stays visible in the list.
_Avoid_: snoozed, silenced

**Hourly count**:
The number of occurrences of one error in one hour; feeds the heat strip.
_Avoid_: bucket, histogram

**Retention**:
How many days occurrences are kept before the pruner deletes them; errors themselves are kept.
_Avoid_: TTL, expiry

### Notifications

**Channel**:
A configured way of delivering notifications (email first), implemented by a module with the `Imison.Notifications.Channel` behaviour.
_Avoid_: integration, provider, notifier

**Rule**:
Whether a trigger notifies.
_Avoid_: alert, policy

**Trigger**:
What a rule fires on: `new`, `regression`, `still_happening` or `digest`.
_Avoid_: event, condition

**Message**:
The channel-neutral content of one notification: trigger, kind, message, location, counts and a link to the error.
_Avoid_: alert, payload

**Delivery**:
A record of one notification sent through one channel, used for throttling and debugging.
_Avoid_: notification log, send

**Digest**:
A daily summary of errors sent instead of single notifications.
_Avoid_: report, summary email
