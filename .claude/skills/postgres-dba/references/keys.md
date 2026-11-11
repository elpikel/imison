# Keys and foreign keys

Examples use an illustrative `Shop` app; adapt names to your repo.

Apps fed by external providers have two table families with different identities. Pick the family
first; the keys follow.

## App-owned tables: Ecto default `id`

Customers, products, orders, order lines, memberships. Ecto's default
`id` (bigserial) is the identity; natural keys get a `unique_index`.

```elixir
create table(:order_lines) do
  add :order_id, references(:orders, on_delete: :delete_all), null: false
  add :product_id, references(:products, on_delete: :restrict), null: false
  add :quantity, :integer, null: false

  timestamps(type: :utc_datetime)
end

create unique_index(:order_lines, [:order_id, :product_id])
```

The schema declares nothing for the key (`@primary_key` defaults to `:id`).

## Provider read models: composite unique key, no `id`

Externally fed tables (the prefixed ones in `.claude/project.md`, e.g.
`supplier_*`) are rebuilt by workers from external data.
Their identity is the combination of external IDs, and it must equal the
upsert `conflict_target`:

```elixir
create table(:supplier_stock_levels, primary_key: false) do
  add :supplier_product_external_id, :integer, null: false
  add :supplier_warehouse_external_id, :integer, null: false
  add :quantity_available, :integer, null: false

  timestamps(type: :utc_datetime)
end

create unique_index(:supplier_stock_levels, [
         :supplier_product_external_id,
         :supplier_warehouse_external_id
       ])
```

```elixir
# in Shop.Workers.SyncSupplierProducts
Repo.insert_all(StockLevel, rows,
  on_conflict: {:replace, [:quantity_available, :updated_at]},
  conflict_target: [
    :supplier_product_external_id,
    :supplier_warehouse_external_id
  ]
)
```

The schema sets `@primary_key false`. A single-key feed table works the same
way: `supplier_products` is keyed by the supplier's integer `external_id`,
`stripe_charges` by Stripe's string id.

## Pure junctions

`primary_key: false`, both columns `null: false`, a `unique_index` on the pair.
No `id`: the pair is the identity.

## Foreign keys

| Target | Column | DB constraint |
|---|---|---|
| App table (`customers`) | `customer_id` via `references/2` | Yes. `on_delete` always explicit: `:delete_all` when the row means nothing without the parent, `:restrict` when the parent must not disappear under it, `:nilify_all` only for genuinely optional links (then `null: true`). |
| Provider data | `<source>_<entity>_external_id`, typed like the provider's id (`:integer` for the supplier, `:string` for Stripe) | Usually none: provider rows arrive out of order, and a worker must not fail on a missing parent. Index the column. |
| Provider table where order is guaranteed | `references(:supplier_products, column: :external_id, type: :integer)` | Allowed when the parent is always written first. |

A missing `on_delete` (defaulting to `:nothing`) is a review finding.

## Don't

- Declare `id serial`; use the default.
- Add a surrogate `id` to a provider read model "just in case".
- Let the upsert `conflict_target` drift from the unique index.
