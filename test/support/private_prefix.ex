defmodule Imison.Test.PrivatePrefix do
  @moduledoc """
  A private Postgres schema for tests that install Imison under a `prefix`.

  `migrate_up/1` runs a migration inside the test's sandbox transaction under
  a version no real migration uses, so the schema is rolled back with the test.
  """

  alias Imison.Test.PrivatePrefix
  alias Imison.Test.Repo

  defmodule Migration do
    @moduledoc false
    use Ecto.Migration

    def up, do: Imison.Migration.up(prefix: PrivatePrefix.name())

    def down, do: Imison.Migration.down(prefix: PrivatePrefix.name())
  end

  @spec name() :: String.t()
  def name, do: "imison_test_private"

  @spec migrate_up(module()) :: pos_integer()
  def migrate_up(migration \\ Migration) do
    version = 99_990_000_000_000 + System.unique_integer([:positive, :monotonic])
    :ok = Ecto.Migrator.up(Repo, version, migration, log: false, migration_lock: false)
    version
  end
end
