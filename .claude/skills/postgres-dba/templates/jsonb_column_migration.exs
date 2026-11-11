defmodule Shop.Repo.Migrations.AddPayloadToSupplierProducts do
  use Ecto.Migration

  def change do
    alter table(:supplier_products) do
      add :payload, :map, null: false, default: %{}
      add :is_discontinued, :boolean, null: false, default: false
    end

    create index(:supplier_products, [:is_discontinued])
  end
end

# Schema fields:
#
#   field :payload, :map, default: %{}
#   field :is_discontinued, :boolean, default: false
#
# Shop.Workers.SyncSupplierProducts writes `payload` and also sets
# `is_discontinued`, because queries filter on it. Fields only displayed stay
# inside `payload`.
