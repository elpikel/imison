defmodule Imison.Analytics.LiveNavigationTest do
  use Imison.ConnCase, async: false

  import ExUnit.CaptureLog
  import Imison.Test.CaptureHelpers

  alias Imison.Analytics.Pageview
  alias Imison.Test.Dashboard
  alias Imison.Test.Repo

  @firefox "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.5; rv:132.0) Gecko/20100101 Firefox/132.0"

  test "loading a LiveView page and connecting its socket is one pageview" do
    name = start_imison(analytics: true)

    {:ok, _view, _html} = @firefox |> browser() |> live("/products")

    flush_pageviews(name)
    assert [%Pageview{path: "/products"}] = Repo.all(Pageview)
  end

  test "following a navigate link to another LiveView is one pageview for the new path, with the page load's visitor" do
    name = start_imison(analytics: true)
    {:ok, view, _html} = @firefox |> browser() |> live("/products")

    assert {:error, {:live_redirect, %{to: "/checkout"}}} = view |> element("a", "Checkout") |> render_click()
    {:ok, _view, _html} = "/products" |> navigating_browser(socket_connect_info(@firefox)) |> live("/checkout")

    flush_pageviews(name)

    assert [%Pageview{path: "/products", visitor_id: visitor_id}, %Pageview{path: "/checkout", visitor_id: visitor_id}] =
             pageviews()
  end

  test "following a navigate link to a LiveView with handle_params is one pageview" do
    name = start_imison(analytics: true)

    {:ok, _view, _html} = "/checkout" |> navigating_browser(socket_connect_info(@firefox)) |> live("/products")

    flush_pageviews(name)
    assert [%Pageview{path: "/products"}] = Repo.all(Pageview)
  end

  test "a navigation whose mount redirects elsewhere is stored only for the page it lands on" do
    name = start_imison(analytics: true)

    assert {:error, {:live_redirect, %{to: "/checkout"}}} =
             "/products" |> navigating_browser(socket_connect_info(@firefox)) |> live("/promo")

    {:ok, _view, _html} = "/promo" |> navigating_browser(socket_connect_info(@firefox)) |> live("/checkout")

    flush_pageviews(name)
    assert [%Pageview{path: "/checkout"}] = Repo.all(Pageview)
  end

  test "following a navigate link to a LiveView without mount is one pageview" do
    name = start_imison(analytics: true)

    {:ok, _view, _html} = "/products" |> navigating_browser(socket_connect_info(@firefox)) |> live("/catalog")

    flush_pageviews(name)
    assert [%Pageview{path: "/catalog"}] = Repo.all(Pageview)
  end

  test "a patch inside a LiveView without mount is one pageview for the new path, with the page load's visitor" do
    name = start_imison(analytics: true)
    {:ok, view, _html} = @firefox |> browser() |> live("/catalog")

    view |> element("a", "Shoes") |> render_click()

    flush_pageviews(name)

    assert [
             %Pageview{path: "/catalog", visitor_id: visitor_id},
             %Pageview{path: "/catalog/shoes", visitor_id: visitor_id}
           ] =
             pageviews()
  end

  test "a patch to a different path is one pageview for that path, with the page load's visitor" do
    name = start_imison(analytics: true)
    {:ok, view, _html} = @firefox |> browser() |> live("/products")

    view |> element("a", "Product 7") |> render_click()

    flush_pageviews(name)

    assert [%Pageview{path: "/products", visitor_id: visitor_id}, %Pageview{path: "/products/7", visitor_id: visitor_id}] =
             pageviews()
  end

  test "with remote_ip_header set, a navigation's visitor comes from the forwarded address the socket shares" do
    name = start_imison(analytics: true, remote_ip_header: "x-forwarded-for")
    @firefox |> browser() |> put_req_header("x-forwarded-for", "203.0.113.7") |> get("/pricing") |> html_response(200)

    {:ok, _view, _html} =
      "/pricing"
      |> navigating_browser(socket_connect_info(@firefox, [{"x-forwarded-for", "203.0.113.7"}]))
      |> live("/checkout")

    flush_pageviews(name)

    assert [%Pageview{path: "/pricing", visitor_id: visitor_id}, %Pageview{path: "/checkout", visitor_id: visitor_id}] =
             pageviews()
  end

  test "a patch that only changes the query is not stored" do
    name = start_imison(analytics: true)
    {:ok, view, _html} = @firefox |> browser() |> live("/products")

    view |> element("a", "Sort by price") |> render_click()

    flush_pageviews(name)
    assert [%Pageview{path: "/products"}] = Repo.all(Pageview)
  end

  test "navigations on a socket that shares no user agent are not stored and log no failure" do
    name = start_imison(analytics: true)

    log =
      capture_log(fn ->
        {:ok, view, _html} = @firefox |> browser() |> put_private(:live_view_connect_info, %{}) |> live("/products")
        view |> element("a", "Product 7") |> render_click()
        {:ok, _view, _html} = "/products" |> navigating_browser(%{}) |> live("/checkout")
        flush_pageviews(name)
      end)

    assert [%Pageview{path: "/products"}] = Repo.all(Pageview)
    refute log =~ "Imison failed"
  end

  test "a navigation by a crawler is not stored" do
    name = start_imison(analytics: true)
    crawler = "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"

    {:ok, _view, _html} = "/products" |> navigating_browser(socket_connect_info(crawler)) |> live("/checkout")

    flush_pageviews(name)
    assert Repo.all(Pageview) == []
  end

  test "a LiveView rendered outside the router is not stored and page loads after it are still counted" do
    name = start_imison(analytics: true)

    {:ok, _view, _html} = @firefox |> browser() |> live_isolated(Imison.Test.CheckoutLive)
    @firefox |> browser() |> get("/pricing") |> html_response(200)

    flush_pageviews(name)
    assert [%Pageview{path: "/pricing"}] = Repo.all(Pageview)
  end

  test "a navigation to a dashboard page is not stored" do
    start_imison(name: Dashboard, analytics: true)

    {:ok, _view, _html} =
      "/errors"
      |> sign_in("admin", "secret")
      |> put_private(:live_view_connect_info, socket_connect_info(@firefox))
      |> put_connect_params(%{"_live_referer" => "http://www.example.com/errors/notifications"})
      |> live("/errors")

    flush_pageviews(Dashboard)
    assert Repo.all(Pageview) == []
  end

  defp browser(user_agent), do: put_req_header(browser_conn(), "user-agent", user_agent)

  # A browser joining a LiveView through a `navigate` link: LiveView's client sends the page it came from as the
  # `_live_referer` connect param and the visitor reaches the socket only through its `connect_info`. The test
  # harness still renders the page over HTTP first; that request carries no user agent, so it isn't counted.
  defp navigating_browser(from_path, connect_info) do
    browser_conn()
    |> put_private(:live_view_connect_info, connect_info)
    |> put_connect_params(%{"_live_referer" => "http://www.example.com" <> from_path})
  end

  defp socket_connect_info(user_agent, x_headers \\ []) do
    %{peer_data: %{address: {127, 0, 0, 1}, port: 51_234, ssl_cert: nil}, user_agent: user_agent, x_headers: x_headers}
  end

  defp pageviews, do: Pageview |> Repo.all() |> Enum.sort_by(& &1.id)
end
