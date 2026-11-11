defmodule Imison.Errors.Occurrence do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "imison_occurrences" do
    belongs_to :error, Imison.Errors.Error

    field :stacktrace, {:array, :map}, default: []
    field :context, :map, default: %{}
    field :release, :string
    field :occurred_at, :utc_datetime_usec
  end
end
