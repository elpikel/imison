defmodule Imison.Capture do
  @moduledoc false

  alias Imison.Capture.Worker
  alias Imison.Errors

  @spec capture(Imison.name(), Errors.occurrence()) :: :ok
  def capture(name, event) do
    with {worker, %{dropped: dropped, queue_limit: queue_limit}} <- Imison.Registry.lookup(name, Worker) do
      if behind?(worker, queue_limit) do
        :counters.add(dropped, 1, 1)
      else
        GenServer.cast(worker, {:record, event})
      end
    end

    :ok
  end

  @spec dropped(Imison.name()) :: non_neg_integer()
  def dropped(name) do
    case Imison.Registry.lookup(name, Worker) do
      {_worker, %{dropped: dropped}} -> :counters.get(dropped, 1)
      nil -> 0
    end
  end

  defp behind?(worker, queue_limit) do
    match?({:message_queue_len, length} when length >= queue_limit, Process.info(worker, :message_queue_len))
  end
end
