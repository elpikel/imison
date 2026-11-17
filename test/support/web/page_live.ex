defmodule Imison.Test.PageLive do
  @moduledoc """
  A LiveView page of the test host app at `/products` and `/products/:id`,
  with `patch` links to another product and to a sorted list, and a
  `navigate` link to `Imison.Test.CheckoutLive`.
  """

  use Phoenix.LiveView

  @impl Phoenix.LiveView
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, product_id: params["id"], sort: params["sort"])}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <h1>Products</h1>
    <.link patch="/products/7">Product 7</.link>
    <.link patch="/products?sort=price">Sort by price</.link>
    <.link navigate="/checkout">Checkout</.link>
    """
  end
end

defmodule Imison.Test.CheckoutLive do
  @moduledoc """
  A LiveView page of the test host app at `/checkout` without `handle_params/3`.
  """

  use Phoenix.LiveView

  @impl Phoenix.LiveView
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <h1>Checkout</h1>
    """
  end
end

defmodule Imison.Test.PromoLive do
  @moduledoc """
  A LiveView page of the test host app at `/promo` whose connected mount
  `push_navigate`s to `/checkout`.
  """

  use Phoenix.LiveView

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket), do: {:ok, push_navigate(socket, to: "/checkout")}, else: {:ok, socket}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <h1>Promo</h1>
    """
  end
end

defmodule Imison.Test.CatalogLive do
  @moduledoc """
  A LiveView page of the test host app at `/catalog` and `/catalog/:section`
  with `handle_params/3` but no `mount/3`, and a `patch` link to a section.
  """

  use Phoenix.LiveView

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket), do: {:noreply, assign(socket, section: params["section"])}

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <h1>Catalog</h1>
    <.link patch="/catalog/shoes">Shoes</.link>
    """
  end
end
