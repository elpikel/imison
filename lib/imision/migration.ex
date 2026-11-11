defmodule Imision.Migration do
  @moduledoc """
  Creates and drops Imision's tables in the host's database, one version at a time.

  The host app calls it from an Ecto migration of its own:

      defmodule MyApp.Repo.Migrations.AddImision do
        use Ecto.Migration

        def up, do: Imision.Migration.up(version: 1)
        def down, do: Imision.Migration.down(version: 1)
      end

  No versions exist yet: both functions return `:ok` and change nothing.
  Version 1 arrives with the first Imision tables (INS-02).
  """

  @doc "Migrates Imision's schema up to the given `:version`."
  @spec up(keyword()) :: :ok
  def up(_opts \\ []), do: :ok

  @doc "Migrates Imision's schema down from the given `:version`."
  @spec down(keyword()) :: :ok
  def down(_opts \\ []), do: :ok
end
