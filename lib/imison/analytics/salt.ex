defmodule Imison.Analytics.Salt do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Query

  alias Imison.Config

  @type t :: %__MODULE__{}

  @salt_bytes 32

  @primary_key {:day, :date, autogenerate: false}
  schema "imison_salts" do
    field :salt, :binary
  end

  @spec for_days(Config.t(), [Date.t()]) :: %{Date.t() => binary()}
  def for_days(%Config{}, []), do: %{}

  def for_days(%Config{repo: repo, prefix: prefix}, days) do
    days = days |> Enum.uniq() |> Enum.sort(Date)

    repo.insert_all(__MODULE__, Enum.map(days, &%{day: &1, salt: :crypto.strong_rand_bytes(@salt_bytes)}),
      prefix: prefix,
      on_conflict: :nothing,
      conflict_target: :day
    )

    __MODULE__
    |> from(as: :salt)
    |> where([salt: salt], salt.day in ^days)
    |> select([salt: salt], %{day: salt.day, salt: salt.salt})
    |> repo.all(prefix: prefix)
    |> Map.new(&{&1.day, &1.salt})
  end
end
