defmodule Imison.Capture.Worker do
  @moduledoc false

  use GenServer

  alias Imison.Capture.FailureLog
  alias Imison.Capture.Filter
  alias Imison.Config
  alias Imison.Errors

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
    if not ignored?(conf, event), do: record(conf, event)
    {:noreply, conf}
  end

  defp ignored?(%Config{ignore: ignore}, %{kind: kind}), do: Enum.any?(ignore, &(inspect(&1) == kind))

  defp record(%Config{release: release, filter: filter_words} = conf, event) do
    storable_event =
      event
      |> Map.update(:context, %{}, &(&1 |> Filter.filter(filter_words) |> json_safe()))
      |> Map.put(:release, release)

    Errors.record(conf, storable_event)
  catch
    kind, reason ->
      FailureLog.error("Imison failed to record a captured event", %{
        kind: kind,
        reason: reason,
        stacktrace: __STACKTRACE__
      })
  end

  defp json_safe(value) when is_binary(value) do
    if String.valid?(value), do: value, else: inspect(value)
  end

  defp json_safe(value) when is_atom(value) or is_number(value), do: value
  defp json_safe(%_struct{} = struct), do: inspect(struct)
  defp json_safe(map) when is_map(map), do: Map.new(map, fn {key, value} -> {json_safe_key(key), json_safe(value)} end)

  defp json_safe(list) when is_list(list) do
    if List.improper?(list), do: inspect(list), else: Enum.map(list, &json_safe/1)
  end

  defp json_safe(value), do: inspect(value)

  defp json_safe_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_safe_key(key) when is_binary(key), do: json_safe(key)
  defp json_safe_key(key), do: inspect(key)
end
