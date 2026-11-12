defmodule Imison.Notifications.Rule do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}
  @type trigger :: :new | :regression | :still_happening | :digest

  @triggers [:new, :regression, :still_happening, :digest]
  @enabled_without_a_stored_rule [:new, :regression]

  @timestamps_opts [type: :utc_datetime_usec]

  schema "imison_rules" do
    field :trigger, Ecto.Enum, values: @triggers
    field :enabled, :boolean, default: true

    timestamps()
  end

  @spec triggers() :: [trigger()]
  def triggers, do: @triggers

  @spec enabled_without_a_stored_rule?(trigger()) :: boolean()
  def enabled_without_a_stored_rule?(trigger), do: trigger in @enabled_without_a_stored_rule
end
