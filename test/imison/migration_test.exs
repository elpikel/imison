defmodule Imison.MigrationTest do
  use Imison.DataCase, async: false

  alias Imison.Test.PrivatePrefix

  @private_prefix PrivatePrefix.name()

  @tables ~w(imison_channels imison_deliveries imison_errors imison_hourly_counts imison_occurrences imison_rules)

  defmodule VersionOneMigration do
    @moduledoc false
    use Ecto.Migration

    def up, do: Imison.Migration.up(version: 1, prefix: PrivatePrefix.name())

    def down, do: Imison.Migration.down(version: 1, prefix: PrivatePrefix.name())
  end

  test "the host's migration creates the six Imison tables in the public schema" do
    assert tables_in("public") == @tables
  end

  test "a second error with the same fingerprint is rejected" do
    fingerprint = insert_error("public", "fingerprint-#{System.unique_integer([:positive])}")

    error = assert_raise Postgrex.Error, fn -> insert_error("public", fingerprint) end

    assert %{code: :unique_violation, constraint: "imison_errors_fingerprint_index"} =
             error.postgres
  end

  test "the host's migration records version 1" do
    assert Imison.Migration.migrated_version(repo: Repo) == 1
  end

  test "running up to version 1 again keeps the tables, their rows and the version" do
    PrivatePrefix.migrate_up(VersionOneMigration)
    fingerprint = insert_error(@private_prefix, "fingerprint-kept")

    PrivatePrefix.migrate_up(VersionOneMigration)

    assert tables_in(@private_prefix) == @tables
    assert migrated_version(@private_prefix) == 1
    assert %{rows: [[^fingerprint]]} = Repo.query!(~s(SELECT fingerprint FROM "#{@private_prefix}".imison_errors))
  end

  test "rolling back version 1 drops the six tables and leaves version 0" do
    version = PrivatePrefix.migrate_up(VersionOneMigration)

    :ok = Ecto.Migrator.down(Repo, version, VersionOneMigration, log: false, migration_lock: false)

    assert tables_in(@private_prefix) == []
    assert migrated_version(@private_prefix) == 0
  end

  test "up with a prefix creates that schema holding the six tables" do
    PrivatePrefix.migrate_up()

    assert %{rows: [[@private_prefix]]} =
             Repo.query!("SELECT schema_name FROM information_schema.schemata WHERE schema_name = $1", [
               @private_prefix
             ])

    assert tables_in(@private_prefix) == @tables
    assert migrated_version(@private_prefix) == 1
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
