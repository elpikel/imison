---
name: postgres-dba
description: >-
  PostgreSQL design for Elixir/Phoenix apps through Ecto: writing migrations
  (`mix ecto.gen.migration`), Ecto schemas and changesets, keys and foreign
  keys, unique and concurrent indexes, `Ecto.Enum` value sets, jsonb/`:map`
  columns, materialized views and other `execute/2` SQL, and table naming with
  the repo's source prefixes (listed in .claude/project.md). Use when adding or changing a table, column, index,
  constraint or view, writing an upsert target, or reviewing a migration.
---

# PostgreSQL through Ecto

The app talks to Postgres only through Ecto. Integrity that must hold for every
writer lives in the schema (NOT NULL, unique indexes, FKs); business rules live
in Elixir context modules. Repo facts (dev DB, test DB, table prefixes) live in
`.claude/project.md`. Read a few of the repo's existing migrations before
writing one: when they conflict with general Postgres advice, the repo wins.
Examples use an illustrative `Shop` app; adapt names to your repo.

## 🎯 Why: design for change

A schema is the hardest thing to change. Consistent keys, prefixes and
upsert targets keep the *next* migration mechanical: add a column, add an
index, never reshape the world.

## Hard rules

1. **Generate, never hand-create.** `mix ecto.gen.migration <verb_noun>`, then
   write the body in the Ecto DSL (`create table`, `alter table`,
   `create index`). Prefer `def change`; use `def up`/`def down` whenever
   `execute/2` is involved.
2. **Verify names before writing.** Read the Ecto schema in `lib/` for every
   table and column you touch. Never guess a table or column name.
3. **Prefix by owner.** Use the table prefixes in `.claude/project.md`.
   App-owned tables (`products`, `orders`, `customers`) have no prefix unless
   `.claude/project.md` says otherwise. **Never write to a prefix marked
   read-only** there: an external pipeline owns those tables.
4. **Keys by table family** (`references/keys.md`):
   - App-owned tables: Ecto's default `id` (bigserial). Don't declare `serial`.
   - Provider read models (externally fed prefixed tables such as `supplier_*`):
     `primary_key: false` plus a composite `unique_index` that is exactly the
     upsert `conflict_target`.
   - Pure junctions: `primary_key: false` plus a `unique_index` on the pair.
5. **Foreign keys.** To app tables: `references(:customers, on_delete: ...)`,
   `null: false` unless the relation is genuinely optional, and `on_delete`
   always explicit. To provider data: a `<source>_<entity>_external_id`
   column typed like the provider's id (e.g. `supplier_product_external_id`,
   `:integer`), indexed, usually without a DB-level FK because provider rows
   arrive out of order.
6. **`null: false` by default** on every column you can't explain being empty.
7. **Value sets are `Ecto.Enum`** over a `:string` column, never Postgres
   `CREATE TYPE`. Add a check constraint only when non-Ecto writers exist
   (`references/enums.md`).
8. **Logic lives in contexts, not the database** (`references/constraints-and-logic.md`).
   No plpgsql. Check the existing migrations for DB functions; keep them to
   SQL wrappers needed for functional indexes (typically an
   `immutable_unaccent` wrapper). A new DB function needs an ADR.
9. **`execute/2` only when the DSL can't express it**: materialized views,
   functional indexes, extensions, check constraints with SQL. Always give a
   matching `down`.
10. **Timestamps:** `timestamps(type: :utc_datetime)` in both the migration and
    the schema for new tables.
11. **Strings:** `:string` for names, codes and labels (the usual default);
    `:text` for unbounded content (bodies, descriptions, URLs that may exceed
    255).
12. **jsonb, not json**: declare `:map` (or `:jsonb`) for document-shaped or
    provider payload data; pull anything you filter or sort on into its own
    column (`references/jsonb.md`).
13. **Indexes on big tables go in concurrently**: `@disable_ddl_transaction
    true`, `@disable_migration_lock true`, `concurrently: true`
    (`references/indexes.md`).
14. **Run migrations on the test DB in `.claude/project.md` only** (`mix test`
    migrates it). Never migrate or roll back the dev DB named there.

## Decision guide

| Situation | Rule | Reference |
|---|---|---|
| Naming a table, column, index | 3 | `references/naming.md` |
| New app-owned table | 4, 5, 10 | `references/keys.md`, `templates/create_table_migration.exs` |
| New provider read model (externally fed) | 4, 5 | `references/keys.md` |
| Upsert from a worker | 4 | `references/keys.md` |
| FK to customers vs. to provider data | 5 | `references/keys.md` |
| Status / type / priority column | 7 | `references/enums.md` |
| Validation that must hold for every writer | 8 | `references/constraints-and-logic.md` |
| Business rule across rows/tables | 8 | `references/constraints-and-logic.md` |
| Search on lower/unaccented text | 9 | `references/derived-data.md` |
| Heavy aggregate read (sales summaries, reports) | 9 | `references/derived-data.md`, `templates/materialized_view_migration.exs` |
| Provider payload or open-ended attributes | 12 | `references/jsonb.md`, `templates/jsonb_column_migration.exs` |
| Index on an existing large table | 13 | `references/indexes.md`, `templates/concurrent_index_migration.exs` |

## Templates

- `templates/create_table_migration.exs`: app-owned table with FK, NOT NULLs,
  unique index, timestamps.
- `templates/schema.ex`: matching Ecto schema with changeset and constraint
  mapping. `order_id` is left out of `cast` on purpose: the context sets it
  (e.g. `Ecto.build_assoc/3`). The template has no comments because `lib/`
  code carries none.
- `templates/materialized_view_migration.exs`: `execute/2` up/down with the
  unique index `REFRESH ... CONCURRENTLY` needs.
- `templates/jsonb_column_migration.exs`: `:map` column plus a hot field
  promoted to its own indexed column.
- `templates/concurrent_index_migration.exs`: index added without locking writes.

## Won't do

- Hand-written migration files, raw `CREATE TABLE` in `execute/2`.
- Postgres enum types, triggers, plpgsql functions.
- Writing to tables under a read-only prefix (`.claude/project.md`).
- Migrating the dev DB.
