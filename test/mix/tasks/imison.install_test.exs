defmodule Mix.Tasks.Imison.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Igniter.Project.Config

  test "configures the repo, the PubSub and the mailer in config.exs" do
    [app_name: :my_app]
    |> phx_test_project()
    |> Igniter.compose_task("imison.install", [])
    |> assert_has_patch("config/config.exs", """
    + |config :my_app, Imison, repo: MyApp.Repo, pubsub: MyApp.PubSub, mailer: MyApp.Mailer
    """)
  end

  test "configures the PubSub the endpoint uses" do
    [app_name: :my_app]
    |> phx_test_project()
    |> Config.configure(
      "config.exs",
      :my_app,
      [MyAppWeb.Endpoint, :pubsub_server],
      MyApp.Events
    )
    |> apply_igniter!()
    |> Igniter.compose_task("imison.install", [])
    |> assert_has_patch("config/config.exs", """
    + |config :my_app, Imison, repo: MyApp.Repo, pubsub: MyApp.Events, mailer: MyApp.Mailer
    """)
  end

  test "leaves the mailer out when the project has no mailer module" do
    [app_name: :my_app]
    |> phx_test_project()
    |> Igniter.rm("lib/my_app/mailer.ex")
    |> apply_igniter!()
    |> Igniter.compose_task("imison.install", [])
    |> assert_has_patch("config/config.exs", """
    + |config :my_app, Imison, repo: MyApp.Repo, pubsub: MyApp.PubSub
    """)
  end

  test "reads the production login from environment variables in runtime.exs" do
    [app_name: :my_app]
    |> phx_test_project()
    |> Igniter.compose_task("imison.install", [])
    |> assert_has_patch("config/runtime.exs", """
    + |  config :my_app, Imison,
    + |    username: System.fetch_env!("IMISON_USER"),
    + |    password: System.fetch_env!("IMISON_PASSWORD")
    """)
  end

  test "sets a login with a random password in dev.exs" do
    igniter =
      [app_name: :my_app]
      |> phx_test_project()
      |> Igniter.compose_task("imison.install", [])

    dev_config = file_content(igniter, "config/dev.exs")

    assert [_match, password] =
             Regex.run(
               ~r/config :my_app, Imison, username: "admin", password: "([^"]+)"/,
               dev_config
             )

    assert String.length(password) == 24
  end

  test "generates a different dev password on each install" do
    passwords =
      for _install <- 1..2 do
        [app_name: :my_app]
        |> phx_test_project()
        |> Igniter.compose_task("imison.install", [])
        |> file_content("config/dev.exs")
        |> then(&Regex.run(~r/password: "([^"]+)"/, &1, capture: :all_but_first))
      end

    assert Enum.uniq(passwords) == passwords
  end

  test "switches capture off and sets a login in test.exs" do
    [app_name: :my_app]
    |> phx_test_project()
    |> Igniter.compose_task("imison.install", [])
    |> assert_has_patch("config/test.exs", """
    + |config :my_app, Imison, enabled: false, username: "test", password: "test"
    """)
  end

  test "starts Imison in the supervision tree after the repo" do
    igniter =
      [app_name: :my_app]
      |> phx_test_project()
      |> Igniter.compose_task("imison.install", [])

    children = file_content(igniter, "lib/my_app/application.ex")

    assert children =~ "{Imison, Application.fetch_env!(:my_app, Imison)}"

    assert position(children, "MyApp.Repo,") <
             position(children, "{Imison, Application.fetch_env!(:my_app, Imison)}")
  end

  test "generates a migration that creates Imison's tables" do
    igniter =
      [app_name: :my_app]
      |> phx_test_project()
      |> Igniter.compose_task("imison.install", [])

    assert [migration_path] = migration_paths(igniter)

    assert_creates(igniter, migration_path, """
    defmodule MyApp.Repo.Migrations.AddImison do
      use Ecto.Migration

      def up, do: Imison.Migration.up(version: 1)

      def down, do: Imison.Migration.down(version: 1)
    end
    """)
  end

  test "mounts the dashboard in a scope piped through the browser pipeline" do
    igniter =
      [app_name: :my_app]
      |> phx_test_project()
      |> Igniter.compose_task("imison.install", [])

    router = file_content(igniter, "lib/my_app_web/router.ex")

    assert router =~ "import Imison.Web.Router"

    assert router =~
             ~r/scope "\/" do\s+pipe_through[ (]:browser\)?\s+imison_dashboard[ (]"\/errors"\)?\s+end/
  end

  test "changes nothing when run a second time" do
    [app_name: :my_app]
    |> phx_test_project()
    |> Igniter.compose_task("imison.install", [])
    |> apply_igniter!()
    |> Igniter.compose_task("imison.install", [])
    |> assert_unchanged()
  end

  defp file_content(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end

  defp position(content, text) do
    {position, _length} = :binary.match(content, text)
    position
  end

  defp migration_paths(igniter) do
    igniter.rewrite.sources
    |> Map.keys()
    |> Enum.filter(&String.ends_with?(&1, "_add_imison.exs"))
  end
end
