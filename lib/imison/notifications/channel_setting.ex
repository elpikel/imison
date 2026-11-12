defmodule Imison.Notifications.ChannelSetting do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @timestamps_opts [type: :utc_datetime_usec]

  schema "imison_channels" do
    field :type, :string
    field :enabled, :boolean, default: true
    field :config, :map, default: %{}

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = channel_setting, attrs) do
    channel_setting
    |> cast(attrs, [:enabled, :config])
    |> validate_required([:type, :enabled, :config])
  end
end
