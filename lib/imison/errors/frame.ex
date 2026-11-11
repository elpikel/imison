defmodule Imison.Errors.Frame do
  @moduledoc false

  @enforce_keys [:module, :function, :arity, :file, :line, :application?]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          module: module(),
          function: atom(),
          arity: non_neg_integer(),
          file: String.t() | nil,
          line: pos_integer() | nil,
          application?: boolean()
        }

  @spec from_stacktrace(Exception.stacktrace(), atom()) :: [t()]
  def from_stacktrace(stacktrace, otp_app), do: Enum.map(stacktrace, &from_stacktrace_entry(&1, otp_app))

  defp from_stacktrace_entry({module, function, arity_or_arguments, location}, otp_app) do
    %__MODULE__{
      module: module,
      function: function,
      arity: arity(arity_or_arguments),
      file: file(location[:file]),
      line: location[:line],
      application?: application_module?(module, otp_app)
    }
  end

  defp arity(arguments) when is_list(arguments), do: length(arguments)
  defp arity(arity), do: arity

  defp file(nil), do: nil
  defp file(file), do: List.to_string(file)

  defp application_module?(module, otp_app), do: :application.get_application(module) == {:ok, otp_app}
end
