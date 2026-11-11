# Naming

Examples use an illustrative `Shop` app; adapt names to your repo.

Lowercase `snake_case`, unquoted, everywhere. If an identifier ever needs
double quotes, it's wrong.

## Tables

- Plural: `orders`, `order_lines`.
- Prefixed by owner when the data comes from a source. The repo's prefixes
  (and which of them are read-only) are in `.claude/project.md`; the `Shop`
  app's, as an example:

| Prefix | Owner |
|---|---|
| `stripe_*` | Stripe webhook handler and sync workers (`stripe_charges`, `stripe_customers`) |
| `supplier_*` | `Shop.Workers.SyncSupplierProducts`, nightly feed via `Shop.Supplier.Client` |

- App-owned tables (`products`, `orders`, `order_lines`, `customers`) have no prefix.

## Columns

- Singular, descriptive, full words: `quantity_available`, not `qty_avl`.
- External references: `<source>_<entity>_external_id`
  (`supplier_product_external_id`); app FKs: `<table_singular>_id` (`customer_id`).
- Timestamps end in `_at` (`paid_at`); dates end in `_on` (`shipped_on`).
- Booleans read as predicates: `is_refunded`, `has_variants`.

## Schemas match columns

The Ecto field name is the column name. Don't rename with `source:` unless the
column is provider-owned and can't change. Before writing any query or
migration, read the schema to get the real table and column names.

## Indexes and constraints

- DSL indexes: let Ecto name them.
- `execute/2` indexes: `<table>_<columns>_<purpose>_idx`.
- Check constraints: `<table>_<column>_check`.

## Domain terms

Use the domain vocabulary (`CONTEXT.md`) in new names, e.g. `customer` over
`user` or `client`, `order_line` over `order_item`.
Existing names that predate the vocabulary stay until a deliberate
migration renames them.
