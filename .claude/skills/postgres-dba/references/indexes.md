# Indexes

Examples use an illustrative `Shop` app; adapt names to your repo.

## What to index

- Every upsert `conflict_target`: a `unique_index`, exactly matching.
- Every `*_external_id` and `*_id` FK column (`customer_id`, `product_id`) used
  in joins or filters.
- Composite indexes in the order queries filter: equality columns first, then
  range or sort columns (`[:status, :inserted_at]`).
- Expressions the query uses verbatim (see `derived-data.md`).

Check with `EXPLAIN ANALYZE` against realistic data before adding one; an
index nobody uses still costs every write.

## New table

Plain `create index` / `create unique_index` inside `def change`. The table is
empty, so locking is harmless.

## Existing large table

Build concurrently so writes aren't blocked:

```elixir
@disable_ddl_transaction true
@disable_migration_lock true

def change do
  create index(:orders, [:status, :inserted_at], concurrently: true)
end
```

A concurrent index can't share a migration with other DDL that needs a
transaction. Put it in its own migration.

## Naming

Let Ecto name DSL indexes (`<table>_<columns>_index`). For `execute/2` indexes,
use `<table>_<columns>_<purpose>_idx`, e.g.
`products_name_lower_unaccent_idx`.
