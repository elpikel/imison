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
    case lookup(imison_name) do
      {_pid, config} ->
        config

      nil ->
        raise RuntimeError, """
        No Imison instance named `#{inspect(imison_name)}` is running and config isn't available.
        """
    end
  end

  @doc """
  Find the `{pid, value}` pair registered for an Imison supervisor or one of its processes.

  Returns `nil` when nothing is registered under that name and role, including when
  `Imison.Registry` itself isn't running (the `:imison` application isn't started)
  and when the registered process has exited but the registry hasn't removed its
  entry yet.

  ## Example

      Imison.Registry.lookup(Imison, Imison.Capture.Worker)
  """
  @spec lookup(Imison.name(), role()) :: nil | {pid(), value()}
  def lookup(imison_name, role \\ nil) do
    __MODULE__
    |> Registry.lookup(key(imison_name, role))
    |> Enum.find(fn {pid, _value} -> Process.alive?(pid) end)
  rescue
    ArgumentError -> nil
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
