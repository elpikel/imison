defmodule Imison.Capture.Handlers do
  @moduledoc false

  use GenServer

  alias Imison.Capture.LoggerHandler
  alias Imison.Capture.Telemetry
  alias Imison.Config

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    %Config{} = conf = Keyword.fetch!(opts, :conf)
    GenServer.start_link(__MODULE__, conf)
  end

  @impl GenServer
  def init(%Config{name: name}) do
    Process.flag(:trap_exit, true)
    detach(name)
    :ok = LoggerHandler.attach(name)
    :ok = Telemetry.attach(name)
    {:ok, name}
  end

  @impl GenServer
  def terminate(_reason, name), do: detach(name)

  defp detach(name) do
    LoggerHandler.detach(name)
    Telemetry.detach(name)
  end
end
