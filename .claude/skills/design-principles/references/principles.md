# Design Principles — Elixir Reference

Each section: the rule → wrong → right → when it's over-engineering.
Examples use an illustrative `Shop` app (`Shop.Catalog`, `Shop.Orders`,
`Shop.Accounts`, a Stripe integration and a supplier product feed); adapt
names to your repo.
Examples follow `.claude/agents/builder.md` conventions.

---

## Coupling — keep it loose; measure it with connascence

**Rule.** Minimise what a module must know about another. Connascence ranks
the knowledge, weakest to strongest: *name* < *type* < *meaning* <
*position* < *algorithm* < *timing*. Weaken it where it crosses modules;
keep strong forms inside one module. Dependencies point toward stable code:
web → contexts → schemas, never back.

**Wrong** — connascence of position and meaning across a context boundary:

```elixir
Catalog.list_products("headphones", 50, 200, 20, true)
```

**Right** — named params in one map; the meaning of `true` ("show member
prices") becomes the customer whose membership decides it:

```elixir
Catalog.list_products(%{
  category: "headphones",
  min_price: 50,
  max_price: 200,
  customer: customer
})
```

**Over-engineering when** both sides live in the same module and change
together; a private two-argument helper doesn't need a params map.

---

## Cohesion — one reason to change

**Rule.** A module groups functions that change for the same reason and are
used together (single responsibility at module scale).

**Wrong** — a grab-bag `Shop.Helpers.Misc` holding price formatting, tax
maths and supplier SKU parsing: three reasons to change, every caller depends
on all of them.

**Right** — each piece lives with its concept: price formatting in
`Shop.Catalog.Pricing`, tax maths in `Shop.Orders.Tax`, SKU parsing in the
`Shop.Supplier` context that owns the feed.

**Over-engineering when** you split a 60-line module that only ever changes
as a unit into four files.

---

## DRY — one authoritative home for each piece of knowledge

**Rule.** Duplicate *knowledge* (a rule, a mapping, a vocabulary) is the
problem; duplicate *characters* aren't.

**Wrong** — two hand-maintained tables in `Shop.Catalog.Categories` encoding
the same category→department fact:

```elixir
@categories_by_department [{"Audio", ["Headphones"]}]
@categories_by_nav_section [%{label: "Electronics", categories: ["Headphones"]}]
```

**Right** — derive the second view from the first:

```elixir
def nav_tree(%{selected_categories: selected_categories, locked: locked}) do
  Departments.nav_sections()
  |> Enum.map(&section_categories(&1, %{selected_categories: selected_categories, locked: locked}))
end
```

**False DRY.** Two functions with identical bodies that encode *different*
decisions (e.g. the order total that earns free shipping vs. the one that
earns a free gift) stay separate. Merging them couples two product decisions.
Rule of Three before extracting.

---

## YAGNI — You Aren't Gonna Need It

**Rule.** Build for today's requirement; keep the seam cheap to add later.

**Wrong** — a `CategoryProvider` behaviour with one static implementation,
"in case categories come from the supplier feed one day".

**Right** — a plain module with a module attribute. If the supplier feed ever
supplies categories, the change is local to `Shop.Catalog.Categories`.

**Over-engineering signal:** a behaviour, config key, or option with exactly
one implementation and no test that needs to swap it.

---

## KISS — keep it simple

**Rule.** The simplest design that works; complexity must pay rent.

**Wrong** — a `__using__` macro generating filter functions per facet, so
nobody can grep where `filter_by_brand/2` is defined.

**Right** — explicit functions, one per facet, pattern-matched on the param:

```elixir
def filter_by_brand(query, []), do: query

def filter_by_brand(query, brands) do
  where(query, [product: product], product.brand in ^brands)
end
```

**Over-engineering when** "simple" means copying a 40-line query five times —
then DRY wins.

---

## Separation of Concerns

**Rule.** Controller parses and authorises, context decides, query module
fetches, JSON view renders. Raw params stop at the controller.

**Wrong** — a context reading request params and building the response:

```elixir
def list_products(conn) do
  conn.params["category"]
  |> build_query()
  |> Repo.all()
  |> Enum.map(&%{"name" => &1.name})
end
```

**Right** — each layer owns one concern (`ShopWeb.ProductController`):

```elixir
def index(conn, params) do
  customer = conn.assigns.current_customer
  products = Catalog.list_products(%{category: Map.get(params, "category"), customer: customer})
  render(conn, :index, products: products)
end
```

**Over-engineering when** a one-off internal task gets controller/context/view
layering it will never need.

---

## Information Hiding — a context's schemas are private

**Rule.** Other contexts call functions, not join on your schemas. The
representation (tables, joins, materialised views) can then change freely.

**Wrong** — `Shop.Orders` joining `supplier_products` with its own query to
check stock, duplicating how `Shop.Supplier` maps supplier SKUs to products.

**Right** — ask the owning context for what you need:

```elixir
in_stock_ids = Supplier.in_stock_product_ids(%{product_ids: product_ids})
```

**Over-engineering when** you add an accessor for every field of a schema
only one context ever reads.

---

## Tell, Don't Ask

**Rule.** Ask the owning module for the decision; don't pull its data out and
decide for it.

**Wrong** — callers interpret the membership themselves:

```elixir
if membership.tier == :premium and DateTime.after?(membership.expires_at, now), do: member_price, else: list_price
```

**Right** — `Membership` owns the interpretation (the access rules live in
`.claude/project.md`):

```elixir
if Membership.premium?(membership), do: member_price, else: list_price
```

**Over-engineering when** the "decision" is rendering — JSON views legitimately
read fields.

---

## Law of Demeter — don't navigate other contexts' graphs

**Rule.** Talk to your immediate collaborator; don't walk preloaded
associations across context boundaries.

**Wrong:**

```elixir
order.customer.membership.plan.discount_rate
```

**Right** — one function answers the question:

```elixir
Accounts.member_discount_rate(%{customer_id: order.customer_id})
```

**Over-engineering when** the chain stays inside one context's own schemas
and is already preloaded for that purpose.

---

## Composition — functions and behaviours, no inheritance

**Rule.** Elixir has no inheritance. Build behaviour by composing small
functions in pipelines and by implementing behaviours. Avoid `use` macros
that inject overridable functions — they recreate inheritance's coupling.

**Wrong** — `use Shop.BaseFilter` injecting `apply/2` with
`defoverridable`, so each filter's real behaviour is split across two files.

**Right** — a pipeline of explicit filter steps:

```elixir
def filter(query, filters) do
  query
  |> filter_by_category(filters.categories)
  |> filter_by_price_range(filters.price_range)
  |> filter_by_brand(filters.brands)
end
```

**Over-engineering when** you invent a pipeline DSL for three steps.

---

## Program to a Behaviour

**Rule.** External systems sit behind a `@callback` contract. Callers depend
on the contract module; the implementation is chosen by config, and tests
swap in a Mox mock (or, without Mox, a test module implementing the
behaviour). This is dependency inversion: the context owns the
contract, the HTTP adapter depends on it.

**Right** — the supplier feed client:

```elixir
defmodule Shop.Supplier.Client do
  @callback list_products() :: {:ok, [map()]} | {:error, term()}

  def list_products, do: client().list_products()

  defp client, do: Application.get_env(:shop, :supplier_client, Shop.Supplier.Client.Http)
end
```

**Wrong** — `Shop.Workers.SyncSupplierProducts` calling `Req.get!/1` against
the supplier API directly, untestable without the network.

**Over-engineering when** you add a behaviour around the app's own contexts or
the Repo. Test those for real against the sandboxed DB.

---

## Command–Query Separation

**Rule.** A function either changes state (returns `{:ok, _}` / `{:error, _}`
or `:ok`) or answers a question (returns data) — not both.

**Wrong** — a getter that writes:

```elixir
def get_open_order(customer_id) do
  Repo.get_by(Order, customer_id: customer_id, status: :open) ||
    Repo.insert!(%Order{customer_id: customer_id, status: :open})
end
```

**Right** — name the command honestly:

```elixir
def get_or_create_open_order(customer_id) do
  Order
  |> Repo.get_by(customer_id: customer_id, status: :open)
  |> ensure_open_order(customer_id)
end
```

**Over-engineering when** an upsert's returned row is genuinely what the
caller needs — return it, but name the function as a command.

---

## Least Astonishment

**Rule.** Names and return shapes match conventions:
- `get_*` returns the value or `nil`; `get_*!` raises.
- `fetch_*` returns `{:ok, value}` / `{:error, reason}`.
- `list_*` returns a list, never `nil`.
- `*?` returns a boolean and has no side effects.

**Wrong** — `fetch_product/1` returning `nil`, or `premium?/1` that writes an
audit row.

**Right** — `fetch_product/1` returns `{:error, :not_found}`;
`Shop.Accounts.Membership.premium?/1` is a pure read.

**Over-engineering when** you rename a stable, widely used function purely
for convention without other reason to touch it.

---

## Fail Fast

**Rule.** Validate at the boundary (controller params, OpenApiSpex, changesets,
webhook payloads), return `{:error, _}` for expected failures, and let
impossible states crash via pattern matching. Fail *closed* where safety
matters: an access check that errors resolves to the most restricted access
(see the access rules in `.claude/project.md`; in `Shop`, a membership check
that errors resolves to non-premium, so the customer sees list prices).

**Wrong** — accepting anything and discovering `nil` three calls deep:

```elixir
def list_products(params), do: build_query(params["category"])
```

**Right** — match the accepted shape and chain dependent steps with `with`:

```elixir
def list_products(%{category_slug: category_slug, min_price: min_price, max_price: max_price}) do
  with {:ok, category} <- Categories.fetch_by_slug(category_slug),
       {:ok, price_range} <- Pricing.parse_range(min_price, max_price) do
    {:ok, query_products(%{category: category, price_range: price_range})}
  end
end
```

**Over-engineering when** you add defensive `nil` checks for values the
type, schema or pattern match already guarantees.
