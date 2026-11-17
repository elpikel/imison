---
status: accepted
---

# Analytics counted server-side, without a client script

Imison counts pageviews from inside the host app, through Phoenix's router-dispatch telemetry and LiveView's `mount` and `handle_params` telemetry, instead of shipping a Plausible-style script that posts to a public ingest route. It runs in the host already and sees every request. Server-side counting needs no change to the host's pages, adds no unauthenticated route (every Imison route still requires the login) and can't be hidden by ad blockers. The costs:
- Bots are filtered by their user agent only, not by "doesn't run JS".
- LiveView navigations need the `/live` socket's `connect_info` to share `:peer_data`, `:user_agent` and `:x_headers`.
- The `/live` socket shares only `x-*` headers, so a `remote_ip_header` outside them (e.g. `cf-connecting-ip`) falls back to the peer address and gives navigations a different visitor than the page load.
- A LiveView with neither `mount/3`, `handle_params/3` nor `on_mount` hooks emits no LiveView telemetry, so navigations to it aren't counted.
- A `navigate` whose `mount/3` succeeds but whose `handle_params/3` redirects is still counted, for the page it redirects away from.
- Visit duration is estimated from the time between pageviews (the last page of a visit counts as zero).
- Pages served from a CDN cache are not counted.

Visitors are identified as Plausible does, without cookies: a hash of a daily salt, the IP and the user agent. The salt is stored in the database so every node computes the same visitor.
