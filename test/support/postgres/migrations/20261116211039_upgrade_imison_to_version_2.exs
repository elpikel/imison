defmodule Imison.Test.Repo.Migrations.UpgradeImisonToVersion2 do
  @moduledoc false
  use Ecto.Migration

  def up, do: Imison.Migration.up(version: 2)

  def down, do: Imison.Migration.down(version: 2)
end
