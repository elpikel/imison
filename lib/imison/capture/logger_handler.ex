defmodule Imison.Capture.LoggerHandler do
  @moduledoc false

  @behaviour :logger_handler

  alias Imison.Capture
  alias Imison.Capture.FailureLog

  @skipped_domains [:imison, :cowboy, :bandit]
  @kept_metadata [:pid, :registered_name]
  @handler_id_range 4_294_967_296

  @spec attach(Imison.name()) :: :ok | {:error, term()}
  def attach(name), do: :logger.add_handler(handler_id(name), __MODULE__, %{config: %{name: name}})

  @spec detach(Imison.name()) :: :ok | {:error, term()}
  def detach(name), do: :logger.remove_handler(handler_id(name))

  @impl :logger_handler
  def log(%{meta: %{crash_reason: crash_reason} = metadata}, %{config: %{name: name}}) do
    if not skipped_domain?(metadata) do
      event = crash_reason |> failure() |> Capture.event(%{metadata: Map.take(metadata, @kept_metadata)})
      Capture.capture(name, event)
    end

    :ok
  catch
    kind, reason ->
      FailureLog.error("Imison failed to capture a crash", %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
  end

  def log(_event, _handler_config), do: :ok

  defp handler_id(name), do: :"#{__MODULE__}.#{:erlang.phash2(name, @handler_id_range)}"

  defp skipped_domain?(metadata) do
    metadata
    |> Map.get(:domain, [])
    |> Enum.any?(&(&1 in @skipped_domains))
  end

  defp failure({{:nocatch, value}, stacktrace}), do: %{kind: :throw, reason: value, stacktrace: stacktrace}

  defp failure({exception, stacktrace}) when is_exception(exception),
    do: %{kind: :error, reason: exception, stacktrace: stacktrace}

  defp failure({reason, stacktrace}), do: %{kind: :exit, reason: reason, stacktrace: stacktrace}
end
