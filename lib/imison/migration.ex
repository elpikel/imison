defmodule Imison.Migration do
  @moduledoc """
  Creates and upgrades Imison's tables in the host's database, one version at a time.

  The host app wraps it in an Ecto migration of its own:

      defmodule MyApp.Repo.Migrations.AddImison do
        use Ecto.Migration

        def up, do: Imison.Migration.up(version: 1)
        def down, do: Imison.Migration.down(version: 1)
      end

  `up()` without a version migrates to the latest version. Versions already
  applied are skipped, so running a version twice changes nothing. When a
  release ships a new version, the host adds one more migration:

      def up, do: Imison.Migration.up(version: 2)
      def down, do: Imison.Migration.down(version: 2)

  `down(version: n)` rolls back every applied version down to and including `n`;
  `down()` removes all of Imison's tables.

  ## Prefixes

  The tables go in the `public` schema unless `prefix:` names another, which
  is created when missing:

      def up, do: Imison.Migration.up(prefix: "private")
      def down, do: Imison.Migration.down(prefix: "private")
  """

  use Ecto.Migration

  @doc "Migrates Imison's tables up to `:version` (default: the latest)."
  @callback up(keyword()) :: :ok

  @doc "Migrates Imison's tables down to and including `:version` (default: the first)."
  @callback down(keyword()) :: :ok

  @doc "Returns the version Imison's tables are migrated to, 0 when they don't exist."
  @callback migrated_version(keyword()) :: non_neg_integer()

  @doc """
  Applies every version not yet applied, up to `:version` (default: the latest).

      Imison.Migration.up()
      Imison.Migration.up(version: 1)
      Imison.Migration.up(prefix: "private")
  """
  @spec up(keyword()) :: :ok
  def up(opts \\ []) when is_list(opts), do: migrator(opts).up(opts)

  @doc """
  Rolls back every applied version down to and including `:version` (default: the first).

      Imison.Migration.down()
      Imison.Migration.down(version: 2)
      Imison.Migration.down(prefix: "private")
  """
  @spec down(keyword()) :: :ok
  def down(opts \\ []) when is_list(opts), do: migrator(opts).down(opts)

  @doc """
  Returns the version Imison's tables are migrated to, 0 when they don't exist.

  Outside a migration, pass the repo:

      Imison.Migration.migrated_version(repo: MyApp.Repo)
  """
  @spec migrated_version(keyword()) :: non_neg_integer()
  def migrated_version(opts \\ []) when is_list(opts), do: migrator(opts).migrated_version(opts)

  defp migrator(opts) do
    repo = Keyword.get_lazy(opts, :repo, &repo/0)

    Ecto.Adapters.Postgres = repo.__adapter__()
    Imison.Migrations.Postgres
  end
end
