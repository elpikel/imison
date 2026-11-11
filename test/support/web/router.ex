defmodule Imison.Test.Router do
  @moduledoc """
  A host router for dashboard tests: the dashboard mounted with `imison_dashboard`
  inside a `:browser` scope at `/errors`, and again at `/admin/errors`.
  """

  use Phoenix.Router, helpers: false

  import Imison.Web.Router
  import Phoenix.LiveView.Router
  import Plug.Conn

  alias Imison.Test.Dashboard

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/" do
    pipe_through(:browser)

    imison_dashboard "/errors", imison_name: Dashboard
  end

  scope "/admin" do
    pipe_through(:browser)

    imison_dashboard "/errors", imison_name: Dashboard, as: :admin_imison_dashboard
  end
end
