defmodule Imison.Errors.Error do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @timestamps_opts [type: :utc_datetime_usec]

  schema "imison_errors" do
    field :fingerprint, :string
    field :kind, :string
    field :message, :string
    field :location, :string
    field :status, Ecto.Enum, values: [:unresolved, :resolved, :ignored], default: :unresolved
    field :muted, :boolean, default: false
    field :first_seen_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :occurrence_count, :integer, default: 0
    field :regressed_at, :utc_datetime_usec
    field :reopened, :boolean, virtual: true, default: false

    timestamps()
  end

  @spec statuses() :: [atom()]
  def statuses, do: Ecto.Enum.values(__MODULE__, :status)

  @spec default_status() :: atom()
  def default_status, do: %__MODULE__{}.status
end
