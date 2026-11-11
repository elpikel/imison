defmodule Imison.Capture.Filter do
  @moduledoc false

  @filtered "[FILTERED]"

  @spec filter(term(), [String.t()]) :: term()
  def filter(value, filter_words) when is_list(filter_words) do
    walk(value, Enum.map(filter_words, &String.downcase/1))
  end

  defp walk(%_struct{} = struct, words) do
    filtered_fields =
      struct
      |> Map.from_struct()
      |> walk_pairs(words)

    Map.merge(struct, filtered_fields)
  end

  defp walk(map, words) when is_map(map), do: walk_pairs(map, words)
  defp walk(list, words) when is_list(list), do: walk_list(list, words)

  defp walk({key, value}, words) do
    {key, filtered_value(key, value, words)}
  end

  defp walk(tuple, words) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&walk(&1, words))
    |> List.to_tuple()
  end

  defp walk(value, _words), do: value

  defp walk_pairs(map, words) do
    Map.new(map, fn {key, value} -> {key, filtered_value(key, value, words)} end)
  end

  defp walk_list([head | tail], words), do: [walk(head, words) | walk_list(tail, words)]
  defp walk_list([], _words), do: []
  defp walk_list(improper_tail, words), do: walk(improper_tail, words)

  defp filtered_value(key, value, words) do
    if sensitive?(key, words), do: @filtered, else: walk(value, words)
  end

  defp sensitive?(key, words) when is_atom(key), do: key |> Atom.to_string() |> sensitive_name?(words)

  defp sensitive?(key, words) when is_binary(key), do: sensitive_name?(key, words)
  defp sensitive?(_key, _words), do: false

  defp sensitive_name?(name, words) do
    downcased = String.downcase(name)
    Enum.any?(words, &String.contains?(downcased, &1))
  end
end
