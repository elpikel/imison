defmodule Imison.Capture.Telemetry do
  @moduledoc false

  alias Imison.Capture
  alias Imison.Capture.FailureLog

  @phoenix_request_exception [:phoenix, :router_dispatch, :exception]
  @oban_job_exception [:oban, :job, :exception]

  @spec attach(Imison.name()) :: :ok | {:error, :already_exists}
  def attach(name) do
    :telemetry.attach_many(
      handler_id(name),
      [@phoenix_request_exception, @oban_job_exception],
      &__MODULE__.handle_event/4,
      %{name: name}
    )
  end

  @spec detach(Imison.name()) :: :ok | {:error, :not_found}
  def detach(name), do: :telemetry.detach(handler_id(name))

  @spec handle_event(:telemetry.event_name(), :telemetry.event_measurements(), :telemetry.event_metadata(), %{
          name: Imison.name()
        }) :: :ok
  def handle_event(event_name, _measurements, metadata, %{name: name}) do
    event =
      metadata
      |> failure()
      |> Capture.event(context(event_name, metadata))

    Capture.capture(name, event)
  catch
    kind, reason ->
      FailureLog.error("Imison failed to capture a telemetry event", %{
        kind: kind,
        reason: reason,
        stacktrace: __STACKTRACE__
      })
  end

  defp handler_id(name), do: {__MODULE__, name}

  defp failure(%{reason: %{__struct__: Plug.Conn.WrapperError, kind: kind, reason: reason, stack: stacktrace}}),
    do: %{kind: kind, reason: reason, stacktrace: stacktrace}

  defp failure(%{kind: kind, reason: reason, stacktrace: stacktrace}),
    do: %{kind: kind, reason: reason, stacktrace: stacktrace}

  defp context(@phoenix_request_exception, %{conn: conn}) do
    %{
      request: %{
        method: conn.method,
        path: conn.request_path,
        params: conn.params,
        headers: Map.new(conn.req_headers)
      }
    }
  end

  defp context(@oban_job_exception, %{job: job}) do
    %{metadata: %{job: Map.take(job, [:worker, :queue, :args, :attempt])}}
  end
end
