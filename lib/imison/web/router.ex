defmodule Imison.Web.Router do
  @moduledoc """
  Mounts the dashboard in the host app's router.

  Import this module in the host's router and call `imison_dashboard/2` inside
  a scope that pipes through the host's `:browser` pipeline (session and CSRF):

      import Imison.Web.Router

      scope "/" do
        pipe_through :browser

        imison_dashboard "/errors"
      end

  The dashboard serves its own stylesheet, fonts and script under the same
  path, so the host's asset pipeline is untouched. The host's endpoint needs
  the LiveView socket at `/live`, as a Phoenix app generated with LiveView has.

  ## Options

    * `:imison_name` - the name of the Imison instance whose errors the
      dashboard shows. Defaults to `Imison`.
    * `:as` - the name of the route and of its `live_session`. Defaults to
      `:imison_dashboard`; mounting the dashboard twice in one router needs a
      different `:as` for each.
  """

  @doc """
  Defines the dashboard routes under `path`.
  """
  defmacro imison_dashboard(path, opts \\ []) do
    opts =
      if Macro.quoted_literal?(opts) do
        Macro.prewalk(opts, &expand_alias(&1, __CALLER__))
      else
        opts
      end

    quote bind_quoted: [path: path, opts: opts] do
      opts = Imison.Web.Router.__options__(opts)
      dashboard_path = Phoenix.Router.scoped_path(__MODULE__, path)

      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

        get "/assets/:digest/*asset", Imison.Web.Assets, [], as: nil

        live_session opts[:as],
          root_layout: {Imison.Web.Layouts, :root},
          session: Imison.Web.Router.__session__(opts, dashboard_path) do
          live "/", Imison.Web.ErrorsLive, :index, as: opts[:as]
        end
      end
    end
  end

  @doc false
  @spec __options__(keyword()) :: keyword()
  def __options__(opts), do: Keyword.validate!(opts, imison_name: Imison, as: :imison_dashboard)

  @doc false
  @spec __session__(keyword(), String.t()) :: map()
  def __session__(opts, dashboard_path), do: %{"imison_name" => opts[:imison_name], "dashboard_path" => dashboard_path}

  defp expand_alias({:__aliases__, _meta, _parts} = alias, env),
    do: Macro.expand(alias, %{env | function: {:imison_dashboard, 2}})

  defp expand_alias(other, _env), do: other
end
