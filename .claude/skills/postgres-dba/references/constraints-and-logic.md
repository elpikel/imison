# Where logic lives: constraints vs. contexts

Examples use an illustrative `Shop` app; adapt names to your repo.

The database guarantees what must hold for **every writer**. Everything else
is Elixir in a context module.

| Concern | Home |
|---|---|
| Column must be present | `null: false` + `validate_required/2` |
| Uniqueness | `unique_index` + `unique_constraint/3` |
| Parent row must exist (app tables) | `references/2` + `foreign_key_constraint/3` |
| Value in a fixed set | `Ecto.Enum` (+ check constraint only if non-Ecto writers exist) |
| Range or shape rules | changeset validations; a `create constraint(..., check: ...)` only if non-Ecto writers exist |
| Business rules (member pricing, stock reservation, premium perks) | Context modules (`Shop.Orders`, `Shop.Accounts`, e.g. `Shop.Accounts.Membership.premium?/1`) |
| Multi-row writes that must succeed together | `Ecto.Multi` or `Repo.transaction/1` in the context |
| Heavy derived reads | Materialized view (see `derived-data.md`) |

## Changeset maps every DB constraint

```elixir
def changeset(%__MODULE__{} = order_line, attrs) do
  order_line
  |> cast(attrs, [:product_id, :quantity, :unit_price])
  |> validate_required([:order_id, :product_id, :quantity, :unit_price])
  |> foreign_key_constraint(:order_id)
  |> foreign_key_constraint(:product_id)
  |> unique_constraint([:order_id, :product_id])
end
```

An unmapped constraint raises instead of returning `{:error, changeset}`.
(`order_id` is set by the context, e.g. via `Ecto.build_assoc/3`, not cast.)

## Database functions

Not a home for business logic. Check the existing migrations first; the usual
legitimate one is `immutable_unaccent`, a one-line `LANGUAGE sql IMMUTABLE`
wrapper that functional indexes require.
A new function, plpgsql or otherwise, needs an ADR. Triggers: don't.
