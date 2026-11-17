defmodule Imison.Analytics.Pageview do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "imison_pageviews" do
    field :visitor_id, :integer
    field :path, :string
    field :source, :string
    field :occurred_at, :utc_datetime_usec
  end
end
