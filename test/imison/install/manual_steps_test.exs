defmodule Imison.Install.ManualStepsTest do
  use ExUnit.Case, async: true

  alias Imison.Install.ManualSteps

  test "configures the repo, the PubSub and the mailer in config.exs with the host's names" do
    steps = ManualSteps.text(:shop_floor)

    assert steps =~ "config/config.exs"

    assert steps =~ """
               config :shop_floor, Imison,
                 repo: ShopFloor.Repo,
                 pubsub: ShopFloor.PubSub,
                 mailer: ShopFloor.Mailer
           """
  end

  test "reads the production login from environment variables inside the prod block of runtime.exs" do
    steps = ManualSteps.text(:shop_floor)

    assert steps =~ "config/runtime.exs, inside `if config_env() == :prod do`"

    assert steps =~ """
               config :shop_floor, Imison,
                 username: System.fetch_env!("IMISON_USER"),
                 password: System.fetch_env!("IMISON_PASSWORD")
           """
  end

  test "asks for a dev password the developer picks instead of a shared default" do
    steps = ManualSteps.text(:shop_floor)

    assert steps =~ "config/dev.exs"
    assert steps =~ ~s|config :shop_floor, Imison, username: "admin", password: "<a password you pick>"|
  end

  test "switches capture off and sets a test login in test.exs" do
    steps = ManualSteps.text(:shop_floor)

    assert steps =~ "config/test.exs"
    assert steps =~ ~s|config :shop_floor, Imison, enabled: false, username: "test", password: "test"|
  end

  test "adds Imison to the application's children after the repo and the PubSub" do
    steps = ManualSteps.text(:shop_floor)

    assert steps =~ "lib/shop_floor/application.ex"
    assert steps =~ "after ShopFloor.Repo and the Phoenix.PubSub child"
    assert steps =~ "{Imison, Application.fetch_env!(:shop_floor, Imison)}"
  end

  test "generates a migration that calls Imison.Migration in the host's repo" do
    steps = ManualSteps.text(:shop_floor)

    assert steps =~ "mix ecto.gen.migration add_imison"

    assert steps =~ """
               defmodule ShopFloor.Repo.Migrations.AddImison do
                 use Ecto.Migration

                 def up, do: Imison.Migration.up(version: 1)
                 def down, do: Imison.Migration.down(version: 1)
               end
           """
  end

  test "imports the dashboard macro and mounts the dashboard in the host's router" do
    steps = ManualSteps.text(:shop_floor)

    assert steps =~ "lib/shop_floor_web/router.ex"
    assert steps =~ "after `use ShopFloorWeb, :router`"

    assert steps =~ """
               import Imison.Web.Router

               scope "/" do
                 pipe_through :browser

                 imison_dashboard "/errors"
               end
           """
  end

  test "adds imison to the formatter's import_deps" do
    steps = ManualSteps.text(:shop_floor)

    assert steps =~ ".formatter.exs"
    assert steps =~ "import_deps: [:imison"
  end

  test "ends with the hint that adding Igniter makes the task do the changes itself" do
    steps = ManualSteps.text(:shop_floor)

    assert steps =~ ~s|{:igniter, "~> 0.8", only: [:dev]}|
    assert steps =~ ~r/mix imison\.install.*make these changes for you\.\n\z/s
  end
end
