defmodule Imison.Notifications.Digest do
  @moduledoc false

  use GenServer

  alias Imison.Capture.FailureLog
  alias Imison.Config
  alias Imison.Notifications

  @default_interval to_timeout(minute: 1)
  @default_initial_delay to_timeout(minute: 1)
  @sending_hour 8

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    %Config{name: name} = conf = Keyword.fetch!(opts, :conf)

    state = %{
      conf: conf,
      now: Keyword.get(opts, :now, &DateTime.utc_now/0),
      schedule: %{
        initial_delay: Keyword.get(opts, :initial_delay, @default_initial_delay),
        interval: Keyword.get(opts, :interval, @default_interval)
      },
      handled_date: nil
    }

    GenServer.start_link(__MODULE__, state, name: Imison.Registry.via(name, __MODULE__))
  end

  @impl GenServer
  def init(%{schedule: %{initial_delay: initial_delay}} = state) do
    send_digest_after(initial_delay)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:send_digest, %{now: now, schedule: %{interval: interval}} = state) do
    state = send_due_digest(state, due_date(now.()))
    send_digest_after(interval)
    {:noreply, state}
  end

  defp due_date(%DateTime{hour: hour} = now) when hour >= @sending_hour, do: now |> DateTime.to_date() |> Date.add(-1)
  defp due_date(%DateTime{}), do: nil

  defp send_due_digest(state, nil), do: state
  defp send_due_digest(%{handled_date: date} = state, date), do: state

  defp send_due_digest(%{conf: conf} = state, date) do
    case Notifications.send_digest(conf, date) do
      :ok -> %{state | handled_date: date}
      :rule_off -> state
    end
  catch
    kind, reason ->
      FailureLog.error("Imison failed to send the daily digest", %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})

      state
  end

  defp send_digest_after(delay), do: Process.send_after(self(), :send_digest, delay)
end
