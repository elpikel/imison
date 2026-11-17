defmodule Imison.BoundedCast do
  @moduledoc false

  @type registration :: %{dropped: :counters.counters_ref(), queue_limit: pos_integer()}

  @spec via(Imison.name(), Imison.Registry.role(), pos_integer()) :: {:via, Registry, tuple()}
  def via(name, role, queue_limit) do
    Imison.Registry.via(name, role, %{dropped: :counters.new(1, [:write_concurrency]), queue_limit: queue_limit})
  end

  @spec cast(Imison.name(), Imison.Registry.role(), term()) :: :ok
  def cast(name, role, message) do
    with {process, %{dropped: dropped, queue_limit: queue_limit}} <- Imison.Registry.lookup(name, role) do
      if behind?(process, queue_limit) do
        :counters.add(dropped, 1, 1)
      else
        GenServer.cast(process, message)
      end
    end

    :ok
  end

  @spec dropped(Imison.name(), Imison.Registry.role()) :: non_neg_integer()
  def dropped(name, role) do
    case Imison.Registry.lookup(name, role) do
      {_process, %{dropped: dropped}} -> :counters.get(dropped, 1)
      nil -> 0
    end
  end

  defp behind?(process, queue_limit) do
    match?({:message_queue_len, length} when length >= queue_limit, Process.info(process, :message_queue_len))
  end
end
