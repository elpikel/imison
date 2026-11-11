defmodule Imison.Capture.Worker do
  @moduledoc false

  use GenServer

  alias Imison.Config
  alias Imison.Errors

  require Logger

  @default_queue_limit 1_000

  @type registration :: %{dropped: :counters.counters_ref(), queue_limit: pos_integer()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    %Config{} = conf = Keyword.fetch!(opts, :conf)

    registration = %{
      dropped: :counters.new(1, [:write_concurrency]),
      queue_limit: Keyword.get(opts, :queue_limit, @default_queue_limit)
    }

    GenServer.start_link(__MODULE__, conf, name: Imison.Registry.via(conf.name, __MODULE__, registration))
  end

  @impl GenServer
  def init(%Config{} = conf), do: {:ok, conf}

  @impl GenServer
  def handle_cast({:record, event}, %Config{} = conf) do
    record(conf, event)
    {:noreply, conf}
  end

  defp record(%Config{release: release} = conf, event) do
    Errors.record(conf, Map.put(event, :release, release))
  catch
    kind, reason ->
      Logger.error(
        "Imison failed to record a captured event: " <> Exception.format(kind, reason, __STACKTRACE__),
        domain: [:imison]
      )
  end
end
