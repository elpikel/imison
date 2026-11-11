defmodule Shop.Orders.OrderLine do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Shop.Catalog.Product
  alias Shop.Orders.Order

  @fulfilment_statuses [:pending, :shipped, :cancelled]

  schema "order_lines" do
    belongs_to :order, Order
    belongs_to :product, Product
    field :quantity, :integer
    field :unit_price, :decimal
    field :fulfilment_status, Ecto.Enum, values: @fulfilment_statuses, default: :pending

    timestamps(type: :utc_datetime)
  end

  def fulfilment_statuses, do: @fulfilment_statuses

  def changeset(%__MODULE__{} = order_line, attrs) do
    order_line
    |> cast(attrs, [:product_id, :quantity, :unit_price, :fulfilment_status])
    |> validate_required([:order_id, :product_id, :quantity, :unit_price])
    |> validate_number(:quantity, greater_than: 0)
    |> foreign_key_constraint(:order_id)
    |> foreign_key_constraint(:product_id)
    |> unique_constraint([:order_id, :product_id])
  end
end
