defmodule Imison.Capture do
  @moduledoc false

  alias Imison.BoundedCast
  alias Imison.Capture.Worker
  alias Imison.Errors

  @type failure :: %{
          required(:kind) => :error | :exit | :throw,
          required(:reason) => term(),
          required(:stacktrace) => Exception.stacktrace(),
          optional(atom()) => term()
        }

  @spec capture(Imison.name(), Errors.occurrence()) :: :ok
  def capture(name, event), do: BoundedCast.cast(name, Worker, {:record, event})

  @spec dropped(Imison.name()) :: non_neg_integer()
  def dropped(name), do: BoundedCast.dropped(name, Worker)

  @spec event(failure(), map()) :: Errors.occurrence()
  def event(%{kind: kind, reason: reason, stacktrace: stacktrace}, context) do
    kind
    |> describe(reason, stacktrace)
    |> Map.merge(%{stacktrace: stacktrace, context: context, occurred_at: DateTime.utc_now()})
  end

  defp describe(:error, reason, stacktrace) do
    exception = Exception.normalize(:error, reason, stacktrace)
    %{kind: inspect(exception.__struct__), message: Exception.message(exception)}
  end

  defp describe(:throw, value, _stacktrace), do: %{kind: "throw", message: inspect(value)}
  defp describe(:exit, reason, _stacktrace), do: %{kind: "exit", message: Exception.format_exit(reason)}
end
