defmodule Imision.Registry do
  @moduledoc """
  Local process storage for Imision instances.
  """

  @type role :: term()
  @type key :: Imision.name() | {Imision.name(), role()}
  @type value :: term()

  @doc false
  def child_spec(_arg) do
    [keys: :unique, name: __MODULE__]
    |> Registry.child_spec()
    |> Supervisor.child_spec(id: __MODULE__)
  end

  @doc """
  Fetch the config of a running Imision instance, raising when none runs under that name.

  ## Example

      Imision.Registry.config(Imision)
  """
  @spec config(Imision.name()) :: Imision.Config.t()
  def config(imision_name) do
    case Registry.lookup(__MODULE__, imision_name) do
      [{_pid, config} | _] ->
        config

      [] ->
        raise RuntimeError, """
        No Imision instance named `#{inspect(imision_name)}` is running and config isn't available.
        """
    end
  end

  @doc """
  Build a via tuple for an Imision supervisor or one of its processes, registering `value` with it.

  ## Example

      Imision.Registry.via(Imision, nil, config)
  """
  @spec via(Imision.name(), role(), value()) ::
          {:via, Registry, {__MODULE__, key()} | {__MODULE__, key(), value()}}
  def via(imision_name, role \\ nil, value \\ nil)
  def via(imision_name, role, nil), do: {:via, Registry, {__MODULE__, key(imision_name, role)}}
  def via(imision_name, role, value), do: {:via, Registry, {__MODULE__, key(imision_name, role), value}}

  defp key(imision_name, nil), do: imision_name
  defp key(imision_name, role), do: {imision_name, role}
end
