# Using the dashboard

The dashboard is mounted wherever you call `imison_dashboard` in your router
(`/imison` after `mix imison.install`). Its screens, under that path:

| Path | Screen |
|---|---|
| `<path>/` | The overview |
| `<path>/errors` | The error list |
| `<path>/errors/<id>` | An error's detail page |
| `<path>/analytics` | Analytics |
| `<path>/notifications` | Notifications |

The top bar links to Overview, Errors, Analytics and Notifications. Each
screen asks for the login set by the `username` and `password` options.

The error list used to be at `<path>/` itself; bookmarks to it now open the
overview.

## Signing in

![The login page](images/login.png)

Every dashboard page except the login page (`<path>/login`) requires
signing in. A correct username and password take you to the overview.
Signing in stores a value derived from the credentials, keyed with the
endpoint's `secret_key_base`, in your app's session cookie. The credentials
themselves are never stored, in the cookie or in the database.

- **Signing out:** "Sign out" in the top bar ends that browser's session.
- **Ending every session:** change the password and restart the app. It's the
  only way, because a copy of the cookie stays valid as long as the username,
  password and `secret_key_base` stay the same.
- **Several nodes:** you stay signed in on every node that shares
  `secret_key_base`.

Failed sign-ins are slowed down so the password can't be guessed by brute
force:

- The first five failures within 15 minutes are free.
- After that, each attempt must wait 1, 2, 4, … seconds after the latest
  failure, at most 5 minutes.
- An attempt during the wait gets "Too many failed sign-ins. Try again in N
  seconds." and isn't checked, so even the right password is refused until the
  wait is over.
- The count is shared by every node, because it is stored in the database.
- If the database can't be reached, sign-in is refused with "Sign-in is
  unavailable. Try again shortly."

## The overview

The dashboard opens on a glimpse of your errors and your traffic, with a
card for each. Each card links to its full page.

- **Errors**: how many errors are unresolved, how many were first seen in
  the last 24 hours (whatever their status now), and the 5 most recently
  seen unresolved errors with their heat strips. The card updates live,
  like the error list.
- **Analytics**: the last 7 days' visitors, pageviews and bounce rate, a
  chart of visitors per day and the top 3 pages, read when the page opens.
  With `analytics: false`, the card says how to turn analytics on.

## The error list

![The error list](images/error-list.png)

An **error** is a group of occurrences with the same fingerprint: the
exception module plus the function (module, name and arity) of the first
frame from your own code. The message is not part of the fingerprint, so
`invalid order id: "abc"` and `invalid order id: "xyz"` are one error, and
the list shows the latest message.

Each row shows:

| Part | What it is |
|---|---|
| Kind | The exception module, or `exit` or `throw` |
| Message | The latest occurrence's message, cut to one line |
| Location | The first frame from your code, as `Module.function/arity (file:line)` |
| Last 24 hours | The heat strip: one bar per hour, darker for more occurrences |
| Events | The number of occurrences, all time |
| Last seen | When the latest occurrence happened |

Two flags can appear next to the kind:

- **Back again**: the error was resolved and has happened since. This is a
  *regression*.
- **Muted**: the error doesn't send notifications. See
  [Muting](#muting-an-error).

The list shows the 100 most recently seen errors of one status. The footer
says how many there are in all.

### Statuses

The tabs switch between the three statuses and show each one's count:

- **Unresolved**: new errors and errors that came back. This is your inbox.
- **Resolved**: errors you marked as fixed. If one happens again, it moves
  back to Unresolved with the **Back again** flag, and a "came back"
  notification is sent.
- **Ignored**: errors you don't want to see. They keep counting
  occurrences, but they stay in Ignored and never notify.

### Searching

![Searching the list](images/search.png)

The search box filters the current tab by text in the kind, message or
location:

- It is case-insensitive.
- It is literal: `%` and `_` are plain characters.
- The tab counts follow the search.

The tab and the search are kept in the URL (`/imison/errors?status=resolved&q=timeout`),
so you can bookmark or share a filtered list.

### Acting on several errors

![Two errors selected](images/bulk-actions.png)

Tick rows, or the box in the header to select all of them, and a bar
appears with the actions that move them out of the current tab: Resolve and
Ignore on Unresolved, Mark unresolved and Ignore on Resolved, and Mark
unresolved and Resolve on Ignored. Other open lists follow the change.

### Live updates

The list updates without a reload: new errors appear, and counts, heat
strips and tab counts change, while your selection and search stay put. The
**Live** indicator in the top bar shows how it updates. Hover over it to see
which mode it is in:

- **With `pubsub` set**, each recorded occurrence is broadcast and the list
  reloads at most once a second, however many errors arrive.
- **Without `pubsub`**, or while the node has no connected nodes, the list
  refreshes from the database every 5 seconds.

Clustering is never required: every node writes to the same database.

## An error's detail page

![An error's detail page](images/error-detail.png)

Click an error's kind to open its detail page. It shows:

- **The header**: the kind, the full message, the status and the location.
- **Actions**: Resolve, Ignore or Mark unresolved, and "Mute notifications"
  (or "Unmute").
- **The counts**: the number of occurrences and when the error was first and
  last seen (UTC).
- **The occurrence**: the latest one, at first. Older and Newer step through
  the rest, one at a time.
- **The stack trace**: frames from your own code have a teal edge. A frame is
  yours when its module belongs to the OTP application of the repo Imison is
  configured with.
- **Request**: for errors raised in a Phoenix request, the method, path,
  params and headers.
- **Logger metadata**: what you passed to `Imison.report/3`, the Oban job
  (worker, queue, args and attempt), or the crashed process.
- **Runtime**: the node that recorded the occurrence and the `release`.

Params, headers and metadata are filtered before they are stored. A key
containing `password`, `token`, `secret`, `authorization` or `cookie` has
its value replaced with `[FILTERED]`. See [the `filter` option](configuration.md#options).

Occurrences older than `retention_days` (30 by default) are deleted every
hour. The error itself is kept, so an old error's detail page still shows its
counts and dates, but no stack trace.

### Muting an error

"Mute notifications" stops the notifications about one error (new, came back
and still happening) while it stays listed and counted under its status. The
daily summary still lists it, because a summary isn't an alert. Unmuting
restores its notifications from its next occurrence.

Use muting for an error you know about and can't fix yet. Use Ignore for an
error you never want to see again.

## Analytics

The Analytics tab (`<path>/analytics`) shows the pageviews Imison counts with
`analytics: true` (see [Analytics](configuration.md#analytics) for turning it
on and what's counted). Pick a range at the top: today, 7 days or 30 days.
Ranges are in UTC and end now: "7 days" is today and the 6 days before it.
The range is kept in the URL (`?range=today`, `7d` or `30d`).

| Part | What it is |
|---|---|
| Visitors | Distinct visitors. A visitor is a hash of the day's salt, the IP and the user agent, so the same person is a new visitor each UTC day: someone who came on 3 days counts 3 times over 7 or 30 days. |
| Pageviews | Page loads and LiveView navigations |
| Bounce rate | The share of visits with a single pageview. A visit is a visitor's pageviews with no gap longer than 30 minutes. |
| Visit duration | The average time from a visit's first to its last pageview. It's an estimate: the time spent on the last page counts as zero, so a bounce lasts 0 seconds. |
| Chart | Visitors per hour for today, per day otherwise, in UTC. Hover a bar to see its hour or day and visitor count. |
| Top pages | The 10 paths with the most visitors, without query strings |
| Top sources | The 10 referring sites with the most visitors. Visitors without a referrer, or coming from a page of your own app, are "Direct / None". |

A few details:

- **Ranges cut visits**: only pageviews inside the range count, so a visit
  that started before the range counts from its first pageview inside it.
- **Midnight UTC** starts a new visitor, so a visit that crosses it counts
  as two.
- **No live updates**: the numbers are read when the page opens and when you
  change the range.
- **Off**: with `analytics: false`, the tab says how to turn analytics on.

## Notifications

The Notifications screen (`<path>/notifications`, linked from the top bar)
sets where alerts go and when. It has its own guide:
[Notifications](notifications.md).

![The Notifications screen](images/notifications.png)
