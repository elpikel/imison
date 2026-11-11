# Template for an endpoint spec. Swap Shop/ShopWeb, the test case, the route
# and the data setup for what .claude/project.md lists. Without a factory,
# replace insert/2 with the project's fixtures, e.g.
# ShopFixtures.product_fixture(%{member_price: Decimal.new("15.00")}).
defmodule ShopWeb.Controllers.ProductController.IndexTest do
  use ShopWeb.ConnCase, async: true

  test "a premium member sees the member price", %{conn: conn} do
    customer = build_premium_customer()
    product = insert(:product, price: Decimal.new("20.00"), member_price: Decimal.new("15.00"))

    response =
      conn
      |> log_in_customer(customer)
      |> get(~p"/api/products")
      |> json_response(200)

    assert [%{"id" => id, "price" => "20.00", "member_price" => "15.00"}] = response["data"]
    assert id == product.id
  end

  test "a non-premium customer sees the regular price only", %{conn: conn} do
    customer = insert(:customer)
    insert(:product, price: Decimal.new("20.00"), member_price: Decimal.new("15.00"))

    response =
      conn
      |> log_in_customer(customer)
      |> get(~p"/api/products")
      |> json_response(200)

    assert [product_json] = response["data"]
    assert %{"price" => "20.00"} = product_json
    refute Map.has_key?(product_json, "member_price")
  end

  test "a member_price param sent by a non-premium customer is ignored", %{conn: conn} do
    customer = insert(:customer)
    insert(:product, price: Decimal.new("20.00"), member_price: Decimal.new("15.00"))

    response =
      conn
      |> log_in_customer(customer)
      |> get(~p"/api/products?member_price=true")
      |> json_response(200)

    assert [product_json] = response["data"]
    refute Map.has_key?(product_json, "member_price")
  end

  defp build_premium_customer do
    customer = insert(:customer)
    insert(:membership, customer: customer, tier: :premium)
    customer
  end
end
