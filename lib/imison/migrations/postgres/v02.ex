defmodule Imison.Migrations.Postgres.V02 do
  @moduledoc false

  use Ecto.Migration

  def up(%{prefix: prefix}) do
    create_if_not_exists table(:imison_pageviews, primary_key: false, prefix: prefix) do
      add :id, :bigserial, primary_key: true
      add :visitor_id, :bigint, null: false
      add :path, :text, null: false
      add :source, :text
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create_if_not_exists index(:imison_pageviews, [:occurred_at], prefix: prefix)

    create_if_not_exists table(:imison_salts, primary_key: false, prefix: prefix) do
      add :day, :date, primary_key: true
      add :salt, :bytea, null: false
    end
  end

  def down(%{prefix: prefix}) do
    drop_if_exists table(:imison_salts, prefix: prefix)
    drop_if_exists table(:imison_pageviews, prefix: prefix)
  end
end
