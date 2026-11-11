defmodule Shop.Repo.Migrations.CreateOrderLines do
  use Ecto.Migration

  def change do
    create table(:order_lines) do
      add :order_id, references(:orders, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :restrict), null: false
      add :quantity, :integer, null: false
      add :unit_price, :decimal, null: false
      add :fulfilment_status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:order_lines, [:order_id, :product_id])
    create index(:order_lines, [:product_id])
  end
end
