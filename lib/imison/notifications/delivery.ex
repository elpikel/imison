defmodule Imison.Notifications.Delivery do
  @moduledoc false

  use Ecto.Schema

  alias Imison.Notifications.Rule

  @type t :: %__MODULE__{}

  schema "imison_deliveries" do
    field :channel_id, :id
    field :error_id, :id
    field :trigger, Ecto.Enum, values: Rule.triggers()
    field :status, Ecto.Enum, values: [:pending, :sent, :failed]
    field :period, :utc_datetime
    field :sent_at, :utc_datetime_usec
  end

  @spec period(Rule.trigger(), DateTime.t()) :: DateTime.t() | nil
  def period(:still_happening, %DateTime{} = last_seen_at),
    do: %{DateTime.truncate(last_seen_at, :second) | minute: 0, second: 0}

  def period(_trigger, _last_seen_at), do: nil

  @spec status(:ok | {:error, term()}) :: atom()
  def status(:ok), do: :sent
  def status({:error, _reason}), do: :failed
end
