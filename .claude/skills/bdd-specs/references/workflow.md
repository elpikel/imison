# Story → tests, worked through

Read this before generating specs.

Examples use the illustrative app `:shop` (`Shop.Catalog`, `Shop.Orders`,
`Shop.Accounts`); adapt names, paths and test cases to what
`.claude/project.md` lists for your repo.

## The mapping

| Source artifact                       | Spec construct                                    |
|---------------------------------------|---------------------------------------------------|
| A story (tracker issue or brainstorm) | Tests in the endpoint, LiveView or module file it exercises |
| An acceptance criterion               | One or more top-level `test` blocks               |
| Each distinct "then …" behaviour      | One `test`, one behaviour asserted                |
| The "given …" state                   | Inline factory or fixture calls at the top of each test |
| A failure / edge "then"               | A `test` placed after all happy-path tests        |

## Worked example

Story:

> **As a** non-premium customer
> **I want** to see regular product prices only
> **So that** member prices stay a benefit of premium membership
>
> - Given a premium member, when they list products, then each product shows
>   its member price.
> - Given a non-premium customer, when they list products, then each product
>   shows the regular price and no member price.
> - Given a non-premium customer who sends a `member_price` param, then the
>   param is ignored and they still see the regular price only.

The rule behind it lives in `Shop.Accounts` (`Membership.premium?/1`); the
behaviour is observed at the product list endpoint, so the tests go into
`test/shop_web/controllers/product_controller/index_test.exs`
(`ShopWeb.Controllers.ProductController.IndexTest`,
`use ShopWeb.ConnCase, async: true`):

1. `test "a premium member sees the member price"`
2. `test "a non-premium customer sees the regular price only"`
3. `test "a member_price param sent by a non-premium customer is ignored"` (sad path, last)

Each test creates its own customer, membership and products (with
`insert(:product)` if `.claude/project.md` lists a factory, otherwise
`ShopFixtures.product_fixture/1` or the context functions), then calls the
route through the router. None is skipped: each stays red until implemented.
A unit test of `Membership.premium?/1` may go in
`test/shop/accounts/membership_test.exs`, but it doesn't replace the
endpoint tests.

### Same story, other entry points

If the product list were a LiveView, the tests go in
`test/shop_web/live/product_live/index_test.exs` and drive it with
`Phoenix.LiveViewTest`:

```elixir
test "a non-premium customer sees the regular price only", %{conn: conn} do
  customer = insert(:customer)
  product = insert(:product, member_price: Decimal.new("15.00"))

  {:ok, view, _html} = conn |> log_in_customer(customer) |> live(~p"/products")

  assert has_element?(view, "#product-#{product.id} [data-role=price]")
  refute has_element?(view, "#product-#{product.id} [data-role=member-price]")
end
```

Background work is specified through the Oban worker's `perform/1`, in the
data test case, with the supplier API mocked (Mox `stub/3`/`expect/4` if the
project uses Mox, otherwise its own seam):

```elixir
test "syncing supplier products stores their member prices" do
  expect(Shop.SupplierMock, :list_products, fn -> {:ok, [%{sku: "SKU-1", member_price: "15.00"}]} end)

  assert :ok = Shop.Workers.SyncSupplierProducts.perform(%Oban.Job{args: %{}})

  assert %{member_price: member_price} = Shop.Catalog.get_product_by_sku!("SKU-1")
  assert Decimal.equal?(member_price, Decimal.new("15.00"))
end
```

## Happy-path checklist

- The nominal case.
- Each boundary the domain allows (none, one, many; first/last page).
- Each distinct success outcome the story's "so that" implies.
- Each access level from the access rules in `.claude/project.md`, where
  the endpoint is access-aware (here: premium member, non-premium customer).
- Each derived value the feature exposes.

## Sad-path checklist

- Each validation rule (missing, malformed, out of range params).
- Not found.
- Unauthorized: wrong pipeline, missing session, token or API key.
- Restricted data requested by a caller the access rules in
  `.claude/project.md` deny (here: a non-premium customer asking for member
  prices).

## Stop point

After writing the files, stop and present them. No implementation until the
user approves. Inside `/implement` (the `builder` subagent), don't stop: the
plan is already approved, so confirm the tests fail for the right reason and
implement.
