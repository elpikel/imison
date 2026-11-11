defmodule Imison.Migrations.Postgres do
  @moduledoc false

  @behaviour Imison.Migration

  use Ecto.Migration

  @initial_version 1
  @current_version 1
  @default_prefix "public"

  @impl Imison.Migration
  def up(opts) do
    opts = with_defaults(opts, @current_version)
    initial = migrated_version(opts)

    cond do
      initial == 0 -> change(@initial_version..opts.version, :up, opts)
      initial < opts.version -> change((initial + 1)..opts.version, :up, opts)
      true -> :ok
    end
  end

  @impl Imison.Migration
  def down(opts) do
    opts = with_defaults(opts, @initial_version)
    initial = max(migrated_version(opts), @initial_version)

    if initial >= opts.version do
      change(initial..opts.version//-1, :down, opts)
    else
      :ok
    end
  end

  @impl Imison.Migration
  def migrated_version(opts) do
    opts = with_defaults(opts, @initial_version)
    repo = Map.get_lazy(opts, :repo, &repo/0)

    query = """
    SELECT pg_catalog.obj_description(pg_class.oid, 'pg_class')
    FROM pg_class
    LEFT JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
    WHERE pg_class.relname = 'imison_errors'
    AND pg_namespace.nspname = '#{opts.escaped_prefix}'
    """

    case repo.query(query, [], log: false) do
      {:ok, %{rows: [[version]]}} when is_binary(version) -> String.to_integer(version)
      _no_version -> 0
    end
  end

  defp change(range, direction, opts) do
    for index <- range do
      padded_index = String.pad_leading(to_string(index), 2, "0")

      [__MODULE__, "V#{padded_index}"]
      |> Module.concat()
      |> apply(direction, [opts])
    end

    case direction do
      :up -> record_version(opts, Enum.max(range))
      :down -> record_version(opts, Enum.min(range) - 1)
    end
  end

  defp record_version(_opts, 0), do: :ok

  defp record_version(%{quoted_prefix: quoted_prefix}, version) do
    execute "COMMENT ON TABLE #{quoted_prefix}.imison_errors IS '#{version}'"
  end

  defp with_defaults(opts, version) do
    opts = Enum.into(opts, %{prefix: @default_prefix, version: version})

    opts
    |> Map.put(:quoted_prefix, inspect(opts.prefix))
    |> Map.put(:escaped_prefix, String.replace(opts.prefix, "'", "''"))
    |> Map.put(:create_schema, opts.prefix != @default_prefix)
  end
end
