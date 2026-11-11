# Value sets: `Ecto.Enum`

Examples use an illustrative `Shop` app; adapt names to your repo.

Don't add Postgres enum types (check the existing migrations; if some exist,
don't add more). Small, code-driven value sets (provider, type, priority,
status) are `Ecto.Enum` over a `:string` column.

## Migration

```elixir
alter table(:orders) do
  add :status, :string, null: false, default: "pending"
end
```

## Schema

```elixir
@statuses [:pending, :paid, :shipped, :cancelled]

schema "orders" do
  field :status, Ecto.Enum, values: @statuses, default: :pending
end

def statuses, do: @statuses
```

Callers use the module function (`Order.statuses()`), never the literal
strings.

## When to add a check constraint

Only when something other than Ecto writes the column (SQL backfills, an
external pipeline). For example, if a reporting job backfills `orders.status`
with raw SQL:

```elixir
create constraint(:orders, :orders_status_check,
         check: "status IN ('pending', 'paid', 'shipped', 'cancelled')"
       )
```

Map it in the changeset with `check_constraint/3` so a violation becomes a
changeset error, not an exception.

## Adding or removing a value

- Add: extend `values:`. No migration unless a check constraint exists (then
  drop and recreate it in `up`/`down`).
- Remove: backfill existing rows first in a migration, then drop the value.

## Lookup table instead?

Only when the set carries extra columns, is edited without a deploy, or churns
often. Static vocabularies (order statuses, membership tiers) stay in code
(e.g. the `@statuses` list on `Shop.Orders.Order`), not tables.

## Don't

- `execute("CREATE TYPE ...")`.
- Hardcode the string values anywhere outside the schema module.
