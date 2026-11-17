defmodule Imison.Test.ShopRouter do
  @moduledoc """
  A host sub-router that `Imison.Test.Router` forwards `/shop` to: an HTML page
  at `/catalog` and the dashboard mounted with `imison_dashboard` at `/errors`.
  """

  use Phoenix.Router, helpers: false

  import Imison.Web.Router

  alias Imison.Test.Dashboard
  alias Imison.Test.PageController

  get("/catalog", PageController, :show)

  imison_dashboard "/errors", imison_name: Dashboard, as: :shop_imison_dashboard
end
