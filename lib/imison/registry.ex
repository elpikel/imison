defmodule Imison.Registry do
  @moduledoc """
  Local process storage for Imison instances.
  """

  @type role :: term()
  @type key :: Imison.name() | {Imison.name(), role()}
  @type value :: term()

  @doc false
  def child_spec(_arg) do
    [keys: :unique, name: __MODULE__]
    |> Registry.child_spec()
    |> Supervisor.child_spec(id: __MODULE__)
  end

  @doc """
  Fetch the config of a running Imison instance, raising when none runs under that name.

  ## Example

      Imison.Registry.config(Imison)
  """
  @spec config(Imison.name()) :: Imison.Config.t()
  def config(imison_name) do
    case Registry.lookup(__MODULE__, imison_name) do
      [{_pid, config} | _] ->
        config

      [] ->
        raise RuntimeError, """
        No Imison instance named `#{inspect(imison_name)}` is running and config isn't available.
        """
    end
  end

  @doc """
  Build a via tuple for an Imison supervisor or one of its processes, registering `value` with it.

  ## Example

      Imison.Registry.via(Imison, nil, config)
  """
  @spec via(Imison.name(), role(), value()) ::
          {:via, Registry, {__MODULE__, key()} | {__MODULE__, key(), value()}}
  def via(imison_name, role \\ nil, value \\ nil)
  def via(imison_name, role, nil), do: {:via, Registry, {__MODULE__, key(imison_name, role)}}
  def via(imison_name, role, value), do: {:via, Registry, {__MODULE__, key(imison_name, role), value}}

  defp key(imison_name, nil), do: imison_name
  defp key(imison_name, role), do: {imison_name, role}
end
