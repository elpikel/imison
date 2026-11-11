---
status: accepted
---

# The database, not the cluster, coordinates nodes

Every node runs its own Imision supervisor against the same Postgres, and every "only once" action is decided by a row: grouping by an `ON CONFLICT` upsert on the unique fingerprint, "new" and "regression" notifications only by the node whose write changed the row, reminders and digests by a unique insert into `imision_deliveries`, failed logins counted in the database. This keeps Imision correct whether or not the nodes are connected by distributed Erlang, so no global process, leader election or `:global` lock is used.
