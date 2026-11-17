defmodule Imison.Analytics.Worker do
  @moduledoc false

  use GenServer

  alias Imison.Analytics
  alias Imison.BoundedCast
  alias Imison.Capture.FailureLog
  alias Imison.Config

  @default_queue_limit 10_000
  @default_flush_interval to_timeout(second: 1)
  @batch_size 100

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    %Config{name: name} = conf = Keyword.fetch!(opts, :conf)

    queue_limit = Keyword.get(opts, :queue_limit, @default_queue_limit)

    state = %{
      conf: conf,
      flush_interval: Keyword.get(opts, :flush_interval, @default_flush_interval),
      flush_timer: nil,
      buffer: [],
      buffered: 0
    }

    GenServer.start_link(__MODULE__, state, name: BoundedCast.via(name, __MODULE__, queue_limit))
  end

  @spec capture(Imison.name(), Analytics.captured_pageview()) :: :ok
  def capture(name, captured_pageview), do: BoundedCast.cast(name, __MODULE__, {:capture, captured_pageview})

  @spec dropped(Imison.name()) :: non_neg_integer()
  def dropped(name), do: BoundedCast.dropped(name, __MODULE__)

  @impl GenServer
  def init(state) do
    Process.flag(:trap_exit, true)
    {:ok, schedule_flush(state)}
  end

  @impl GenServer
  def handle_cast({:capture, captured_pageview}, %{buffer: buffer, buffered: buffered} = state) do
    buffered_state = %{state | buffer: [captured_pageview | buffer], buffered: buffered + 1}

    if buffered_state.buffered >= @batch_size do
      {:noreply, flush(buffered_state)}
    else
      {:noreply, buffered_state}
    end
  end

  @impl GenServer
  def handle_info(:flush, state) do
    {:noreply, state |> flush() |> schedule_flush()}
  end

  @impl GenServer
  def terminate(_reason, state), do: flush(state)

  defp flush(%{buffered: 0} = state), do: state

  defp flush(%{conf: conf, buffer: buffer} = state) do
    record(conf, Enum.reverse(buffer))
    %{state | buffer: [], buffered: 0}
  end

  defp record(conf, captured_pageviews) do
    Analytics.record_pageviews(conf, captured_pageviews)
  catch
    kind, reason ->
      FailureLog.error("Imison failed to record pageviews", %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
  end

  defp schedule_flush(%{flush_timer: flush_timer, flush_interval: flush_interval} = state) do
    if flush_timer, do: Process.cancel_timer(flush_timer)
    %{state | flush_timer: Process.send_after(self(), :flush, flush_interval)}
  end
end
