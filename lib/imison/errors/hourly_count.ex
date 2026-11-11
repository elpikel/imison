defmodule Imison.Errors.HourlyCount do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "imison_hourly_counts" do
    belongs_to :error, Imison.Errors.Error

    field :hour, :utc_datetime
    field :count, :integer, default: 0
  end
end
