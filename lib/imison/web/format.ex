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

  @spec duration(non_neg_integer()) :: String.t()
  def duration(seconds) when seconds < 60, do: "#{seconds}s"
  def duration(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
  def duration(seconds), do: "#{div(seconds, 3600)}h #{seconds |> rem(3600) |> div(60)}m"

  @spec percentage(0..100) :: String.t()
  def percentage(percent), do: "#{percent}%"
end
