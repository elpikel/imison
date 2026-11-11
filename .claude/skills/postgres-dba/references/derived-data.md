# Derived data: functional indexes and materialized views

Examples use an illustrative `Shop` app; adapt names to your repo.

Check the existing migrations for generated columns first; prefer the forms
already in use. Derived data takes one of two forms.

## Functional indexes (search, normalised lookup)

For case- and accent-insensitive search, index the expression instead of
storing a copy:

```elixir
@disable_ddl_transaction true
@disable_migration_lock true

def up do
  execute("""
  CREATE INDEX CONCURRENTLY IF NOT EXISTS products_name_lower_unaccent_idx
  ON products (lower(immutable_unaccent(name)))
  """)
end

def down do
  execute("DROP INDEX CONCURRENTLY IF EXISTS products_name_lower_unaccent_idx")
end
```

The query must use the identical expression or the index is ignored:

```elixir
Product
|> from(as: :product)
|> where([product: product], fragment("lower(immutable_unaccent(?))", product.name) == ^normalised_query)
```

## Materialized views (heavy aggregate reads)

Used for sales summaries, reports and similar wide reads. Rules:

- Created and dropped with `execute/2` in `up`/`down`. Changing the definition
  means drop and recreate, in the same migration.
- Needs a `UNIQUE INDEX` so `REFRESH MATERIALIZED VIEW CONCURRENTLY` works.
- Refreshed by a background job (an Oban worker, e.g.
  `Shop.Workers.RefreshProductSalesSummaries`, or the repo's scheduler if
  `.claude/project.md` lists no background jobs), never per request.
- Read through an Ecto schema with `@primary_key false`. Select only the
  columns you need: summary views tend to grow wide.
- Profile the defining query with `EXPLAIN ANALYZE` before blaming the
  refresh mechanism: the cost is usually the query, not the refresh.

See `templates/materialized_view_migration.exs` (`product_sales_summaries`,
aggregated from `order_lines`).

## A stored generated column?

Allowed if a value is filtered or sorted often and a functional index can't
serve it. Add it with `execute/2` (`ALTER TABLE ... ADD COLUMN ... GENERATED
ALWAYS AS (...) STORED`) and a `down`. If the repo has none yet, note the reason
in the PR.
