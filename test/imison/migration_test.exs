defmodule Imison.MigrationTest do
  use Imison.DataCase, async: false

  alias Imison.Test.PrivatePrefix

  @private_prefix PrivatePrefix.name()

  @version_one_tables ~w(imison_channels imison_deliveries imison_errors imison_hourly_counts imison_login_failures imison_occurrences imison_rules)

  @tables Enum.sort(@version_one_tables ++ ~w(imison_pageviews imison_salts))

  defmodule VersionOneMigration do
    @moduledoc false
    use Ecto.Migration

    def up, do: Imison.Migration.up(version: 1, prefix: PrivatePrefix.name())

    def down, do: Imison.Migration.down(version: 1, prefix: PrivatePrefix.name())
  end

  defmodule VersionTwoMigration do
    @moduledoc false
    use Ecto.Migration

    def up, do: Imison.Migration.up(version: 2, prefix: PrivatePrefix.name())

    def down, do: Imison.Migration.down(version: 2, prefix: PrivatePrefix.name())
  end

  defmodule FreshInstallMigration do
    @moduledoc false
    use Ecto.Migration

    alias Imison.Migrations.Postgres

    def up, do: Imison.Migration.up(version: Postgres.current_version(), prefix: PrivatePrefix.name())

    def down, do: Imison.Migration.down(version: Postgres.initial_version(), prefix: PrivatePrefix.name())
  end

  test "the host's migrations create the nine Imison tables in the public schema" do
    assert tables_in("public") == @tables
  end

  test "a second error with the same fingerprint is rejected" do
    fingerprint = insert_error("public", "fingerprint-#{System.unique_integer([:positive])}")

    error = assert_raise Postgrex.Error, fn -> insert_error("public", fingerprint) end

    assert %{code: :unique_violation, constraint: "imison_errors_fingerprint_index"} =
             error.postgres
  end

  test "the host's migrations record version 2" do
    assert Imison.Migration.migrated_version(repo: Repo) == 2
  end

  test "running up to version 1 again keeps the tables, their rows and the version" do
    PrivatePrefix.migrate_up(VersionOneMigration)
    fingerprint = insert_error(@private_prefix, "fingerprint-kept")

    PrivatePrefix.migrate_up(VersionOneMigration)

    assert tables_in(@private_prefix) == @version_one_tables
    assert migrated_version(@private_prefix) == 1
    assert %{rows: [[^fingerprint]]} = Repo.query!(~s(SELECT fingerprint FROM "#{@private_prefix}".imison_errors))
  end

  test "rolling back version 1 drops the seven tables and leaves version 0" do
    version = PrivatePrefix.migrate_up(VersionOneMigration)

    :ok = Ecto.Migrator.down(Repo, version, VersionOneMigration, log: false, migration_lock: false)

    assert tables_in(@private_prefix) == []
    assert migrated_version(@private_prefix) == 0
  end

  test "up with a prefix creates that schema holding the nine tables" do
    PrivatePrefix.migrate_up()

    assert %{rows: [[@private_prefix]]} =
             Repo.query!("SELECT schema_name FROM information_schema.schemata WHERE schema_name = $1", [
               @private_prefix
             ])

    assert tables_in(@private_prefix) == @tables
    assert migrated_version(@private_prefix) == 2
  end

  test "version 2 adds the pageviews table, indexed on occurred_at" do
    PrivatePrefix.migrate_up(VersionTwoMigration)

    assert columns_in(@private_prefix, "imison_pageviews") == [
             %{name: "id", type: "bigint", nullable: false},
             %{name: "visitor_id", type: "bigint", nullable: false},
             %{name: "path", type: "text", nullable: false},
             %{name: "source", type: "text", nullable: true},
             %{name: "occurred_at", type: "timestamp without time zone", nullable: false}
           ]

    assert "CREATE INDEX imison_pageviews_occurred_at_index ON #{@private_prefix}.imison_pageviews USING btree (occurred_at)" in index_definitions(
             @private_prefix,
             "imison_pageviews"
           )
  end

  test "version 2 adds the salts table, keyed by day" do
    PrivatePrefix.migrate_up(VersionTwoMigration)

    assert columns_in(@private_prefix, "imison_salts") == [
             %{name: "day", type: "date", nullable: false},
             %{name: "salt", type: "bytea", nullable: false}
           ]

    insert_salt(@private_prefix, ~D[2026-11-16])

    error = assert_raise Postgrex.Error, fn -> insert_salt(@private_prefix, ~D[2026-11-16]) end

    assert %{code: :unique_violation, constraint: "imison_salts_pkey"} = error.postgres
  end

  test "upgrading from version 1 to version 2 adds the analytics tables and keeps the error rows" do
    PrivatePrefix.migrate_up(VersionOneMigration)
    fingerprint = insert_error(@private_prefix, "fingerprint-upgraded")

    PrivatePrefix.migrate_up(VersionTwoMigration)

    assert tables_in(@private_prefix) == @tables
    assert migrated_version(@private_prefix) == 2
    assert %{rows: [[^fingerprint]]} = Repo.query!(~s(SELECT fingerprint FROM "#{@private_prefix}".imison_errors))
  end

  test "rolling back version 2 drops the analytics tables and leaves version 1" do
    version = PrivatePrefix.migrate_up(VersionTwoMigration)

    :ok = Ecto.Migrator.down(Repo, version, VersionTwoMigration, log: false, migration_lock: false)

    assert tables_in(@private_prefix) == @version_one_tables
    assert migrated_version(@private_prefix) == 1
  end

  test "rolling back a fresh install to the current version drops every Imison table and leaves version 0" do
    version = PrivatePrefix.migrate_up(FreshInstallMigration)

    :ok = Ecto.Migrator.down(Repo, version, FreshInstallMigration, log: false, migration_lock: false)

    assert tables_in(@private_prefix) == []
    assert migrated_version(@private_prefix) == 0
  end

  defp migrated_version(prefix), do: Imison.Migration.migrated_version(repo: Repo, prefix: prefix)

  defp tables_in(prefix) do
    %{rows: rows} =
      Repo.query!(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = $1 AND table_name LIKE 'imison\\_%' ORDER BY table_name",
        [prefix]
      )

    List.flatten(rows)
  end

  defp columns_in(prefix, table) do
    %{rows: rows} =
      Repo.query!(
        "SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema = $1 AND table_name = $2 ORDER BY ordinal_position",
        [prefix, table]
      )

    Enum.map(rows, fn [name, type, nullable] -> %{name: name, type: type, nullable: nullable == "YES"} end)
  end

  defp index_definitions(prefix, table) do
    %{rows: rows} =
      Repo.query!("SELECT indexdef FROM pg_indexes WHERE schemaname = $1 AND tablename = $2", [prefix, table])

    List.flatten(rows)
  end

  defp insert_salt(prefix, day) do
    Repo.query!(~s[INSERT INTO "#{prefix}".imison_salts (day, salt) VALUES ($1, $2)], [day, :crypto.strong_rand_bytes(16)])
  end

  defp insert_error(prefix, fingerprint) do
    Repo.query!(
      """
      INSERT INTO "#{prefix}".imison_errors
        (fingerprint, kind, message, first_seen_at, last_seen_at, inserted_at, updated_at)
      VALUES ($1, 'RuntimeError', 'boom', now(), now(), now(), now())
      """,
      [fingerprint]
    )

    fingerprint
  end
end
