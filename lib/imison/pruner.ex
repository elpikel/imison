defmodule Imison.Pruner do
  @moduledoc false

  use GenServer

  alias Imison.Analytics
  alias Imison.Capture.FailureLog
  alias Imison.Config
  alias Imison.Errors

  @default_interval to_timeout(hour: 1)
  @default_initial_delay to_timeout(minute: 1)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    %Config{name: name} = conf = Keyword.fetch!(opts, :conf)

    schedule = %{
      initial_delay: Keyword.get(opts, :initial_delay, @default_initial_delay),
      interval: Keyword.get(opts, :interval, @default_interval)
    }

    GenServer.start_link(__MODULE__, %{conf: conf, schedule: schedule}, name: Imison.Registry.via(name, __MODULE__))
  end

  @impl GenServer
  def init(%{schedule: %{initial_delay: initial_delay}} = state) do
    prune_after(initial_delay)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:prune, %{conf: conf, schedule: %{interval: interval}} = state) do
    prune(conf)
    prune_after(interval)
    {:noreply, state}
  end

  defp prune(conf) do
    now = DateTime.utc_now()
    logging_failure("Imison failed to prune old occurrences", fn -> Errors.prune(conf, now) end)
    logging_failure("Imison failed to prune old pageviews", fn -> Analytics.prune(conf, now) end)
  end

  defp logging_failure(failure_summary, pruning) do
    pruning.()
  catch
    kind, reason ->
      FailureLog.error(failure_summary, %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
  end

  defp prune_after(delay), do: Process.send_after(self(), :prune, delay)
end
