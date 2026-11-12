defmodule Imison.Notifications.ReminderMemo do
  @moduledoc false

  alias Imison.Errors.Error
  alias Imison.Notifications.Delivery

  @type t :: %__MODULE__{period: DateTime.t() | nil, error_ids: MapSet.t(pos_integer())}

  defstruct period: nil, error_ids: MapSet.new()

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec hand_off(t(), Error.t()) :: {:hand_off | :already_handed_off, t()}
  def hand_off(%__MODULE__{} = memo, %Error{id: error_id, last_seen_at: last_seen_at}) do
    period = Delivery.period(:still_happening, last_seen_at)

    cond do
      memo.period == nil or DateTime.after?(period, memo.period) ->
        {:hand_off, %__MODULE__{period: period, error_ids: MapSet.new([error_id])}}

      DateTime.before?(period, memo.period) ->
        {:hand_off, memo}

      MapSet.member?(memo.error_ids, error_id) ->
        {:already_handed_off, memo}

      true ->
        {:hand_off, %{memo | error_ids: MapSet.put(memo.error_ids, error_id)}}
    end
  end
end
