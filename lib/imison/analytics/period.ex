defmodule Imison.Analytics.Period do
  @moduledoc false

  @type range :: :today | :last_7_days | :last_30_days
  @type bucket :: :hour | :day

  @type t :: %{
          starts_at: DateTime.t(),
          ends_at: DateTime.t(),
          bucket: bucket(),
          bucket_starts: [DateTime.t()]
        }

  @hours_in_day 24

  @spec new(range(), DateTime.t()) :: t()
  def new(:today, now), do: spanning_days(now, %{days: 1, bucket: :hour})
  def new(:last_7_days, now), do: spanning_days(now, %{days: 7, bucket: :day})
  def new(:last_30_days, now), do: spanning_days(now, %{days: 30, bucket: :day})

  defp spanning_days(now, %{days: days, bucket: bucket}) do
    utc_now = DateTime.shift_zone!(now, "Etc/UTC")

    starts_at =
      utc_now
      |> DateTime.to_date()
      |> Date.add(1 - days)
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    %{
      starts_at: starts_at,
      ends_at: utc_now,
      bucket: bucket,
      bucket_starts: bucket_starts(starts_at, %{days: days, bucket: bucket})
    }
  end

  defp bucket_starts(starts_at, %{bucket: :hour}) do
    Enum.map(0..(@hours_in_day - 1), &DateTime.shift(starts_at, hour: &1))
  end

  defp bucket_starts(starts_at, %{days: days, bucket: :day}) do
    Enum.map(0..(days - 1), &DateTime.shift(starts_at, day: &1))
  end
end
