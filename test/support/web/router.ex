defmodule Imison.Test.Router do
  @moduledoc """
  A host router for dashboard tests: the dashboard mounted with `imison_dashboard`
  inside a `:browser` scope at `/errors`, and again at `/admin/errors`, next to
  the host's own pages (`Imison.Test.PageController`): an HTML page at
  `/pricing` (GET and POST), a redirect at `/plans` and JSON at `/api/status`,
  `/shop` forwarded to the sub-router `Imison.Test.ShopRouter`, and LiveView
  pages at `/products`, `/products/:id` (`Imison.Test.PageLive`),
  `/checkout` (`Imison.Test.CheckoutLive`), `/promo` (`Imison.Test.PromoLive`)
  and `/catalog`, `/catalog/:section` (`Imison.Test.CatalogLive`) in one
  `live_session`.
  """

  use Phoenix.Router, helpers: false

  import Imison.Web.Router
  import Phoenix.LiveView.Router
  import Plug.Conn

  alias Imison.Test.CatalogLive
  alias Imison.Test.CheckoutLive
  alias Imison.Test.Dashboard
  alias Imison.Test.PageController
  alias Imison.Test.PageLive
  alias Imison.Test.PromoLive
  alias Imison.Test.ShopRouter

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/" do
    pipe_through(:browser)

    get("/pricing", PageController, :show)
    post("/pricing", PageController, :show)
    get("/plans", PageController, :moved)

    live_session :shop do
      live("/products", PageLive, :index)
      live("/products/:id", PageLive, :show)
      live("/checkout", CheckoutLive, :show)
      live("/promo", PromoLive, :show)
      live("/catalog", CatalogLive, :index)
      live("/catalog/:section", CatalogLive, :show)
    end

    imison_dashboard "/errors", imison_name: Dashboard

    forward("/shop", ShopRouter)
  end

  scope "/api" do
    get("/status", PageController, :status)
  end

  scope "/admin" do
    pipe_through(:browser)

    imison_dashboard "/errors", imison_name: Dashboard, as: :admin_imison_dashboard
  end
end
