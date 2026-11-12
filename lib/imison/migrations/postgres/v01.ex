defmodule Imison.Migrations.Postgres.V01 do
  @moduledoc false

  use Ecto.Migration

  def up(%{create_schema: create_schema?, prefix: prefix, quoted_prefix: quoted_prefix}) do
    if create_schema?, do: execute("CREATE SCHEMA IF NOT EXISTS #{quoted_prefix}")

    error_reference = references(:imison_errors, on_delete: :delete_all, prefix: prefix, type: :bigint)
    channel_reference = references(:imison_channels, on_delete: :delete_all, prefix: prefix, type: :bigint)

    create_if_not_exists table(:imison_errors, primary_key: false, prefix: prefix) do
      add :id, :bigserial, primary_key: true
      add :fingerprint, :text, null: false
      add :kind, :text, null: false
      add :message, :text, null: false
      add :location, :text
      add :status, :text, null: false, default: "unresolved"
      add :muted, :boolean, null: false, default: false
      add :first_seen_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :occurrence_count, :bigint, null: false, default: 0
      add :regressed_at, :utc_datetime_usec

      timestamps type: :utc_datetime_usec
    end

    create_if_not_exists unique_index(:imison_errors, [:fingerprint], prefix: prefix)
    create_if_not_exists index(:imison_errors, [:status, :last_seen_at], prefix: prefix)

    create_if_not_exists table(:imison_occurrences, primary_key: false, prefix: prefix) do
      add :id, :bigserial, primary_key: true

      add :error_id, error_reference, null: false

      add :stacktrace, :jsonb, null: false, default: fragment("'[]'::jsonb")
      add :context, :jsonb, null: false, default: fragment("'{}'::jsonb")
      add :release, :text
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create_if_not_exists index(:imison_occurrences, [:error_id, :occurred_at], prefix: prefix)
    create_if_not_exists index(:imison_occurrences, [:occurred_at], prefix: prefix)

    create_if_not_exists table(:imison_hourly_counts, primary_key: false, prefix: prefix) do
      add :id, :bigserial, primary_key: true

      add :error_id, error_reference, null: false

      add :hour, :utc_datetime, null: false
      add :count, :bigint, null: false, default: 0
    end

    create_if_not_exists unique_index(:imison_hourly_counts, [:error_id, :hour], prefix: prefix)
    create_if_not_exists index(:imison_hourly_counts, [:hour], prefix: prefix)

    create_if_not_exists table(:imison_channels, primary_key: false, prefix: prefix) do
      add :id, :bigserial, primary_key: true
      add :type, :text, null: false
      add :enabled, :boolean, null: false, default: true
      add :config, :jsonb, null: false, default: fragment("'{}'::jsonb")

      timestamps type: :utc_datetime_usec
    end

    create_if_not_exists unique_index(:imison_channels, [:type], prefix: prefix)

    create_if_not_exists table(:imison_rules, primary_key: false, prefix: prefix) do
      add :id, :bigserial, primary_key: true
      add :trigger, :text, null: false
      add :enabled, :boolean, null: false, default: true

      timestamps type: :utc_datetime_usec
    end

    create_if_not_exists unique_index(:imison_rules, [:trigger], prefix: prefix)

    create_if_not_exists table(:imison_deliveries, primary_key: false, prefix: prefix) do
      add :id, :bigserial, primary_key: true

      add :channel_id, channel_reference, null: false

      add :error_id, error_reference
      add :trigger, :text, null: false
      add :status, :text, null: false
      add :period, :utc_datetime
      add :sent_at, :utc_datetime_usec
    end

    create_if_not_exists unique_index(:imison_deliveries, [:channel_id, :error_id, :trigger, :period], prefix: prefix)
    create_if_not_exists index(:imison_deliveries, [:error_id], prefix: prefix)

    create_if_not_exists table(:imison_login_failures, primary_key: false, prefix: prefix) do
      add :id, :bigserial, primary_key: true
      add :failed_at, :utc_datetime_usec, null: false
    end

    create_if_not_exists index(:imison_login_failures, [:failed_at], prefix: prefix)
  end

  def down(%{prefix: prefix}) do
    drop_if_exists table(:imison_login_failures, prefix: prefix)
    drop_if_exists table(:imison_deliveries, prefix: prefix)
    drop_if_exists table(:imison_rules, prefix: prefix)
    drop_if_exists table(:imison_channels, prefix: prefix)
    drop_if_exists table(:imison_hourly_counts, prefix: prefix)
    drop_if_exists table(:imison_occurrences, prefix: prefix)
    drop_if_exists table(:imison_errors, prefix: prefix)
  end
end
