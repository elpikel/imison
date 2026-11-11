defmodule Imison.Test.Repo.Migrations.AddImison do
  @moduledoc false
  use Ecto.Migration

  def up, do: Imison.Migration.up()

  def down, do: Imison.Migration.down()
end
