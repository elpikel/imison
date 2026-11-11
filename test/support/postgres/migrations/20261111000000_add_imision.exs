defmodule Imision.Test.Repo.Migrations.AddImision do
  @moduledoc false
  use Ecto.Migration

  def up, do: Imision.Migration.up()

  def down, do: Imision.Migration.down()
end
