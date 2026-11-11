---
status: proposed
---

# Built-in dashboard login

The dashboard has its own session login with one username and password from `IMISION_USER` and `IMISION_PASSWORD`, compared with `Plug.Crypto.secure_compare/2`, so the route is mounted in every environment and works without the host's user system. Unlike Oban Web, it is not limited to dev routes. Open: an option to sit behind the host's admin auth instead, and a read-only second login.
