defmodule Shop.Repo.Migrations.AddStatusInsertedAtIndexToOrders do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:orders, [:status, :inserted_at], concurrently: true)
  end
end
