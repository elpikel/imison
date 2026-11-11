defmodule Imison.Web.Format do
  @moduledoc false

  @spec with_thousands_separators(non_neg_integer()) :: String.t()
  def with_thousands_separators(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  @spec status_label(atom()) :: String.t()
  def status_label(status), do: status |> Atom.to_string() |> String.capitalize()

  @spec utc_time(DateTime.t()) :: String.t()
  def utc_time(datetime), do: Calendar.strftime(datetime, "%-d %b %Y, %H:%M:%S UTC")
end
