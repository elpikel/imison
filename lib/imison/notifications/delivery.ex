defmodule Imison.Notifications.Delivery do
  @moduledoc false

  use Ecto.Schema

  alias Imison.Notifications.Rule

  @type t :: %__MODULE__{}

  schema "imison_deliveries" do
    field :channel_id, :id
    field :error_id, :id
    field :trigger, Ecto.Enum, values: Rule.triggers()
    field :status, Ecto.Enum, values: [:sent, :failed]
    field :sent_at, :utc_datetime_usec
  end

  @spec status(:ok | {:error, term()}) :: atom()
  def status(:ok), do: :sent
  def status({:error, _reason}), do: :failed
end
