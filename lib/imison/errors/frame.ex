defmodule Imison.Errors.Frame do
  @moduledoc false

  @enforce_keys [:module, :function, :arity, :file, :line]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          module: module(),
          function: atom(),
          arity: non_neg_integer(),
          file: String.t() | nil,
          line: pos_integer() | nil
        }

  @spec from_stacktrace(Exception.stacktrace()) :: [t()]
  def from_stacktrace(stacktrace), do: Enum.map(stacktrace, &from_stacktrace_entry/1)

  defp from_stacktrace_entry({module, function, arity_or_arguments, location}) do
    %__MODULE__{
      module: module,
      function: function,
      arity: arity(arity_or_arguments),
      file: file(location[:file]),
      line: location[:line]
    }
  end

  defp arity(arguments) when is_list(arguments), do: length(arguments)
  defp arity(arity), do: arity

  defp file(nil), do: nil
  defp file(file), do: List.to_string(file)
end
