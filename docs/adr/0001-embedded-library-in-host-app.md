---
status: accepted
---

# Embedded library using the host's repo, not a separate service

Imision is a Hex library that runs in the host app's supervision tree and stores errors in the host's Postgres through the host's Ecto repo, installed the way Oban is. A separate service would need its own deployment, backups and secrets; embedding reuses what the app already has. The cost: a database outage cannot be recorded, only logged. Whether to also support a separate repo is still open (`docs/PROJECT.md`, Open decisions).
