defmodule Imison.Install.ManualSteps do
  @moduledoc false

  alias Imison.Install
  alias Imison.Migrations.Postgres

  @spec text(atom()) :: String.t()
  def text(app_name) when is_atom(app_name) do
    app_literal = inspect(app_name)
    app_dir = Atom.to_string(app_name)
    module_prefix = Macro.camelize(app_dir)
    current_version = Postgres.current_version()
    initial_version = Postgres.initial_version()
    dashboard_path = Install.dashboard_path()
    live_socket_path = Install.live_socket_path()
    visitor_details = Enum.map_join(Install.visitor_details(), ", ", &inspect/1)

    """
    mix imison.install needs Igniter to edit your project. To install Imison by hand,
    make these changes:

    1. config/config.exs (pubsub is your endpoint's pubsub_server; leave mailer out
       unless the app sends email through a Swoosh mailer):

        config #{app_literal}, Imison,
          repo: #{module_prefix}.Repo,
          pubsub: #{module_prefix}.PubSub,
          mailer: #{module_prefix}.Mailer

    2. config/runtime.exs, inside `if config_env() == :prod do`:

        config #{app_literal}, Imison,
          username: System.fetch_env!("IMISON_USER"),
          password: System.fetch_env!("IMISON_PASSWORD")

    3. config/dev.exs, with a dev password you pick:

        config #{app_literal}, Imison, username: "admin", password: "<a password you pick>"

    4. config/test.exs, so tests record nothing:

        config #{app_literal}, Imison, enabled: false, username: "test", password: "test"

    5. lib/#{app_dir}/application.ex, in the children list after #{module_prefix}.Repo and the Phoenix.PubSub child:

        {Imison, Application.fetch_env!(#{app_literal}, Imison)}

    6. A migration: run `mix ecto.gen.migration add_imison` and fill it in:

        defmodule #{module_prefix}.Repo.Migrations.AddImison do
          use Ecto.Migration

          def up, do: Imison.Migration.up(version: #{current_version})
          def down, do: Imison.Migration.down(version: #{initial_version})
        end

    7. lib/#{app_dir}_web/router.ex: import the macro after `use #{module_prefix}Web, :router`,
       then mount the dashboard:

        import Imison.Web.Router

        scope "/" do
          pipe_through :browser

          imison_dashboard "#{dashboard_path}"
        end

    8. .formatter.exs: add :imison to import_deps, so imison_dashboard needs no parentheses:

        import_deps: [:imison, ...]

    9. lib/#{app_dir}_web/endpoint.ex: add :peer_data, :user_agent and :x_headers to the LiveView
       socket's connect_info, so analytics can read the visitor's address and user agent
       (harmless while analytics is off):

        socket "#{live_socket_path}", Phoenix.LiveView.Socket,
          websocket: [connect_info: [#{visitor_details}, session: @session_options]],
          longpoll: [connect_info: [#{visitor_details}, session: @session_options]]

    10. Optional, to count pageviews: turn analytics on in config/config.exs. Behind a proxy,
        also set remote_ip_header to the header carrying the visitor's address:

        config #{app_literal}, Imison, analytics: true, remote_ip_header: "x-forwarded-for"

    Then run `mix ecto.migrate`: the dashboard is at #{dashboard_path}. In production, set
    IMISON_USER and IMISON_PASSWORD.

    To skip the hand edits, add #{Install.igniter_dependency()} to your deps,
    run `mix deps.get`, then run `mix imison.install` again: it will make these changes for you.
    """
  end
end
