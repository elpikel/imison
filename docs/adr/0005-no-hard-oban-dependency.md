---
status: proposed
---

# No hard Oban dependency

Background work (notification delivery, pruning) runs on Imison's own `Task.Supervisor` and a pruner process, so a host app without Oban can install it. Oban is optional: when present, only its job-failure hook is attached. Open: delivering notifications through the host's Oban when it is present, to get retries.
