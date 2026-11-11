defmodule Imison.Capture.FailureLog do
  @moduledoc false

  require Logger

  @spec error(String.t(), Imison.Capture.failure()) :: :ok
  def error(summary, %{kind: kind, reason: reason, stacktrace: stacktrace}) do
    stacktrace_without_arguments = Enum.map(stacktrace, &without_arguments/1)

    banner = banner(kind, reason, stacktrace_without_arguments)
    formatted_stacktrace = Exception.format_stacktrace(stacktrace_without_arguments)
    Logger.error("#{summary}: #{banner}\n#{formatted_stacktrace}", domain: [:imison])
  end

  defp banner(:error, reason, stacktrace) do
    exception =
      case Exception.normalize(:error, reason, stacktrace) do
        %FunctionClauseError{} = function_clause_error -> %{function_clause_error | args: nil}
        exception -> exception
      end

    Exception.format_banner(:error, exception, stacktrace)
  end

  defp banner(kind, reason, stacktrace), do: Exception.format_banner(kind, reason, stacktrace)

  defp without_arguments({module, function, arguments, location}) when is_list(arguments),
    do: {module, function, length(arguments), location}

  defp without_arguments(entry), do: entry
end
