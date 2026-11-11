# jsonb columns

Examples use an illustrative `Shop` app; adapt names to your repo.

Use jsonb for provider payloads and genuinely open-ended, document-shaped
data. Never `json`. In a migration, `:map` and `:jsonb` both create a jsonb
column; in the schema the field is `:map` (or `{:array, :map}`).

## Relational spine, jsonb body

Columns you filter, sort, join or upsert on are real columns. The rest can sit
in the document:

`stripe_charges` is the model: keyed on Stripe's string id (`stripe_id`), the
raw Stripe response in `payload` (`:map`), and the fields reports and the
order flow query on (`stripe_customer_external_id`, `amount`, `status`,
`is_refunded`, `paid_at`, …) as real columns. `is_refunded` lives outside the
payload because refund reports filter on it. That's the pattern: if a query
needs a field, it gets a column, set by the code that writes the payload.

## Querying inside a document

Only for occasional reads. Keep it in pipe syntax with named bindings:

```elixir
StripeCharge
|> from(as: :charge)
|> where([charge: charge], fragment("?->>'currency' = ?", charge.payload, ^currency))
```

If this shows up on a hot path, promote the field to a column or add a GIN
index (`execute/2`, `CREATE INDEX CONCURRENTLY ... USING gin (payload)`).

## Don't

- Store data in jsonb that you join on.
- Build an EAV ("key", "value") table; use a `:map` column instead.
- Hold large provider responses in jsonb when only a few fields are read;
  extract those fields in the worker.
