defmodule Mix.Tasks.Imison.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs Imison in a Phoenix app"
  end

  def example do
    "mix imison.install"
  end

  def manual_short_doc do
    "Prints the steps to install Imison in a Phoenix app (Igniter makes them for you)"
  end

  def manual_long_doc do
    """
    Prints the steps to install Imison in a Phoenix app by hand, filled with the
    app's name and modules: its config, its place in the supervision tree, the
    migration that creates its tables, the dashboard route and the formatter.
    It changes no file.

    ## Example

    ```sh
    #{example()}
    ```

    With `#{Imison.Install.igniter_dependency()}` in the app's deps, the same task
    makes these changes itself.
    """
  end

  def long_doc do
    """
    Installs Imison in a Phoenix app: its config, its place in the supervision
    tree, the migration that creates its tables and the dashboard route.

    ## Example

    ```sh
    #{example()}
    mix ecto.migrate
    ```

    `mix igniter.install imison` adds the dependency and runs this task in one step.

    ## Changes

      * `config/config.exs`: `repo`, `pubsub` (the endpoint's `pubsub_server`)
        and, when the app has a `Mailer` module, `mailer`
      * `config/runtime.exs`: the production login, from the `IMISON_USER` and
        `IMISON_PASSWORD` environment variables
      * `config/dev.exs`: the login `admin` with a password generated at install time
      * `config/test.exs`: `enabled: false` and a test login
      * the application's children: `{Imison, Application.fetch_env!(:my_app, Imison)}`
        after the repo and the PubSub
      * a migration `add_imison` calling `Imison.Migration`
      * the router: `import Imison.Web.Router` and `imison_dashboard "/errors"`
        in a scope piped through `:browser`
      * `.formatter.exs`: `:imison` in `import_deps`

    A change that is already there is skipped, so running the task again changes nothing.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Imison.Install do
    @shortdoc __MODULE__.Docs.short_doc()

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    alias Igniter.Code.Common
    alias Igniter.Code.Function
    alias Igniter.Code.Keyword, as: KeywordCode
    alias Igniter.Libs.Ecto, as: EctoLibrary
    alias Igniter.Libs.Phoenix, as: PhoenixLibrary
    alias Igniter.Project.Application, as: ProjectApplication
    alias Igniter.Project.Config
    alias Igniter.Project.Formatter
    alias Igniter.Project.Module, as: ProjectModule
    alias Imison.Install
    alias Imison.Migrations.Postgres

    @dev_username "admin"
    @dev_password_bytes 18
    @test_credential "test"

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :imison,
        example: __MODULE__.Docs.example()
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      case EctoLibrary.select_repo(igniter) do
        {igniter, nil} ->
          Igniter.add_issue(igniter, """
          No Ecto repo found. Imison stores errors through the app's repo:
          add one, then run `mix imison.install` again.
          """)

        {igniter, repo} ->
          install(igniter, %{app_name: ProjectApplication.app_name(igniter), repo: repo})
      end
    end

    defp install(igniter, host) do
      igniter
      |> Formatter.import_dep(:imison)
      |> configure_shared(host)
      |> configure_production_login(host.app_name)
      |> configure_dev_login(host.app_name)
      |> configure_test(host.app_name)
      |> supervise(host)
      |> generate_migration(host.repo)
      |> mount_dashboard()
      |> Igniter.add_notice("""
      Imison is installed. Run `mix ecto.migrate` to create its tables; the
      dashboard is at #{Install.dashboard_path()}. In production, set IMISON_USER and
      IMISON_PASSWORD; the dev login is in config/dev.exs.
      """)
    end

    defp configure_shared(igniter, host) do
      igniter
      |> Config.configure_new("config.exs", host.app_name, [Imison, :repo], module_code(host.repo))
      |> Config.configure_new(
        "config.exs",
        host.app_name,
        [Imison, :pubsub],
        module_code(pubsub(igniter, host.app_name))
      )
      |> configure_mailer(host.app_name)
    end

    defp configure_mailer(igniter, app_name) do
      mailer = ProjectModule.module_name(igniter, "Mailer")

      case ProjectModule.module_exists(igniter, mailer) do
        {true, igniter} ->
          Config.configure_new(igniter, "config.exs", app_name, [Imison, :mailer], module_code(mailer))

        {false, igniter} ->
          igniter
      end
    end

    defp configure_production_login(igniter, app_name) do
      igniter
      |> Config.configure_runtime_env(:prod, app_name, [Imison, :username], fetch_env_code("IMISON_USER"),
        updater: &{:ok, &1}
      )
      |> Config.configure_runtime_env(:prod, app_name, [Imison, :password], fetch_env_code("IMISON_PASSWORD"),
        updater: &{:ok, &1}
      )
    end

    defp configure_dev_login(igniter, app_name) do
      igniter
      |> Config.configure_new("dev.exs", app_name, [Imison, :username], @dev_username)
      |> Config.configure_new("dev.exs", app_name, [Imison, :password], random_password())
    end

    defp configure_test(igniter, app_name) do
      igniter
      |> Config.configure_new("test.exs", app_name, [Imison, :enabled], false)
      |> Config.configure_new("test.exs", app_name, [Imison, :username], @test_credential)
      |> Config.configure_new("test.exs", app_name, [Imison, :password], @test_credential)
    end

    defp supervise(igniter, host) do
      child_config = quote(do: Application.fetch_env!(unquote(host.app_name), Imison))

      ProjectApplication.add_new_child(igniter, {Imison, {:code, child_config}}, after: [host.repo, Phoenix.PubSub])
    end

    defp generate_migration(igniter, repo) do
      EctoLibrary.gen_migration(igniter, repo, "add_imison",
        body: """
        def up, do: Imison.Migration.up(version: #{Postgres.current_version()})

        def down, do: Imison.Migration.down(version: #{Postgres.current_version()})
        """,
        on_exists: :skip
      )
    end

    defp mount_dashboard(igniter) do
      case PhoenixLibrary.select_router(igniter) do
        {igniter, nil} ->
          Igniter.add_warning(igniter, """
          No Phoenix router found. Mount the dashboard in your router by hand:

              import Imison.Web.Router

              scope "/" do
                pipe_through :browser

                imison_dashboard "#{Install.dashboard_path()}"
              end
          """)

        {igniter, router} ->
          if mounts_dashboard?(igniter, router) do
            igniter
          else
            igniter
            |> import_dashboard_macro(router)
            |> PhoenixLibrary.add_scope(
              "/",
              """
              pipe_through :browser

              imison_dashboard #{inspect(Install.dashboard_path())}
              """,
              router: router,
              placement: :after
            )
          end
      end
    end

    defp mounts_dashboard?(igniter, router) do
      case ProjectModule.find_module(igniter, router) do
        {:ok, {_igniter, _source, zipper}} ->
          Function.move_to_function_call(zipper, :imison_dashboard, [1, 2]) != :error

        {:error, _igniter} ->
          false
      end
    end

    defp import_dashboard_macro(igniter, router) do
      ProjectModule.find_and_update_module!(igniter, router, fn zipper ->
        with :error <- move_to_dashboard_import(zipper),
             {:ok, zipper} <- PhoenixLibrary.move_to_router_use(igniter, zipper) do
          {:ok, Common.add_code(zipper, "import Imison.Web.Router")}
        else
          {:ok, _import} -> {:ok, zipper}
          :error -> {:warning, "Could not add `import Imison.Web.Router` to #{inspect(router)}."}
        end
      end)
    end

    defp move_to_dashboard_import(zipper) do
      Function.move_to_function_call(zipper, :import, 1, &Function.argument_equals?(&1, 0, Imison.Web.Router))
    end

    defp pubsub(igniter, app_name) do
      case endpoint_pubsub(igniter, app_name) do
        {:ok, pubsub} -> pubsub
        :error -> ProjectModule.module_name(igniter, "PubSub")
      end
    end

    defp endpoint_pubsub(igniter, app_name) do
      config_path = ProjectApplication.config_path(igniter)
      igniter = Igniter.include_existing_file(igniter, config_path, required?: false)

      with {:ok, source} <- Rewrite.source(igniter.rewrite, config_path),
           zipper = source |> Rewrite.Source.get(:quoted) |> Sourceror.Zipper.zip(),
           {:ok, config} <- move_to_config_with_pubsub_server(zipper, app_name),
           {:ok, options} <- Function.move_to_nth_argument(config, 2),
           {:ok, pubsub_server} <- KeywordCode.get_key(options, :pubsub_server),
           pubsub when is_atom(pubsub) and not is_nil(pubsub) <-
             ProjectModule.to_module_name(pubsub_server.node) do
        {:ok, pubsub}
      else
        _not_found -> :error
      end
    end

    defp move_to_config_with_pubsub_server(zipper, app_name) do
      Function.move_to_function_call_in_current_scope(zipper, :config, 3, fn config ->
        Function.argument_equals?(config, 0, app_name) and
          Function.argument_matches_predicate?(
            config,
            2,
            &KeywordCode.keyword_has_path?(&1, [:pubsub_server])
          )
      end)
    end

    defp fetch_env_code(variable) do
      {:code, Sourceror.parse_string!(~s|System.fetch_env!("#{variable}")|)}
    end

    defp module_code(module) do
      {:code, module |> inspect() |> Sourceror.parse_string!()}
    end

    defp random_password do
      @dev_password_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64()
    end
  end
else
  defmodule Mix.Tasks.Imison.Install do
    @shortdoc __MODULE__.Docs.manual_short_doc()

    @moduledoc __MODULE__.Docs.manual_long_doc()

    use Mix.Task

    alias Imison.Install.ManualSteps

    @impl Mix.Task
    def run(_argv) do
      case Mix.Project.config()[:app] do
        nil -> Mix.raise("Run `mix imison.install` inside the Phoenix app's project, not an umbrella root.")
        app_name -> app_name |> ManualSteps.text() |> Mix.shell().info()
      end
    end
  end
end
