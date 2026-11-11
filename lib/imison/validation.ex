defmodule Imison.Validation do
  @moduledoc false

  @spec validate_schema(opts :: keyword(), schema :: keyword()) :: :ok | {:error, String.t()}
  def validate_schema(opts, schema) when is_list(schema) do
    Enum.reduce_while(opts, :ok, fn {key, value}, :ok ->
      case validate_option(schema, key, value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_option(schema, key, value) do
    case Keyword.fetch(schema, key) do
      {:ok, type} -> validate_type(type, key, value)
      :error -> unknown_error(key, Keyword.keys(schema))
    end
  end

  defp validate_type(:any, _key, _value), do: :ok

  defp validate_type(nil, key, value) do
    if is_nil(value) do
      :ok
    else
      {:error, "expected #{inspect(key)} to be nil, got: #{inspect(value)}"}
    end
  end

  defp validate_type(:atom, key, value) do
    if is_atom(value) do
      :ok
    else
      {:error, "expected #{inspect(key)} to be an atom, got: #{inspect(value)}"}
    end
  end

  defp validate_type(:boolean, key, value) do
    if is_boolean(value) do
      :ok
    else
      {:error, "expected #{inspect(key)} to be a boolean, got: #{inspect(value)}"}
    end
  end

  defp validate_type({:list, type}, key, value) when is_list(value) do
    if Enum.all?(value, &(:ok == validate_type(type, key, &1))) do
      :ok
    else
      {:error, "expected #{inspect(key)} to be a list of #{inspect(type)}, got: #{inspect(value)}"}
    end
  end

  defp validate_type({:list, _type}, key, value) do
    {:error, "expected #{inspect(key)} to be a list, got: #{inspect(value)}"}
  end

  defp validate_type({:module, functions}, key, value) do
    cond do
      not (is_atom(value) and Code.ensure_loaded?(value)) ->
        {:error, "expected #{inspect(key)} to be a loaded module, got: #{inspect(value)}"}

      not Enum.all?(functions, fn {function, arity} -> function_exported?(value, function, arity) end) ->
        {:error, "expected #{inspect(key)} to implement #{inspect(functions)}, got: #{inspect(value)}"}

      true ->
        :ok
    end
  end

  defp validate_type({:or, types}, key, value) do
    if Enum.any?(types, &(:ok == validate_type(&1, key, value))) do
      :ok
    else
      {:error, "expected #{inspect(key)} to be one of #{inspect(types)}, got: #{inspect(value)}"}
    end
  end

  defp validate_type(:pos_integer, key, value) do
    if is_integer(value) and value > 0 do
      :ok
    else
      {:error, "expected #{inspect(key)} to be a positive integer, got: #{inspect(value)}"}
    end
  end

  defp validate_type(:string, key, value) do
    if is_binary(value) do
      :ok
    else
      {:error, "expected #{inspect(key)} to be a string, got: #{inspect(value)}"}
    end
  end

  defp validate_type(type, _key, _value) do
    raise ArgumentError, "unknown schema type: #{inspect(type)}"
  end

  defp unknown_error(name, known) do
    name = to_string(name)

    known
    |> Enum.map(fn field -> {String.jaro_distance(name, to_string(field)), field} end)
    |> Enum.sort(:desc)
    |> case do
      [{score, field} | _] when score > 0.7 ->
        {:error, "unknown option :#{name}, did you mean :#{field}?"}

      _ ->
        {:error, "unknown option :#{name}"}
    end
  end
end
