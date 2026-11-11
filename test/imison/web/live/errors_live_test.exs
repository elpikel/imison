defmodule Imison.Web.ErrorsLiveTest do
  use Imison.ConnCase, async: false

  import Imison.Test.CaptureHelpers

  alias Imison.Test.Dashboard

  test "the dashboard mounted with imison_dashboard serves the error list page" do
    start_imison(name: Dashboard, enabled: false)

    {:ok, view, html} = live(browser_conn(), "/errors")

    assert html =~ ~s(<h1 class="page__title">Errors</h1>)
    assert has_element?(view, ".topbar .brand", "Imison")
    assert has_element?(view, ".nav .nav__link[aria-current=page]", "Errors")
    assert has_element?(view, ".panel .empty .empty__title", "No unresolved errors")
  end

  test "the dashboard mounted at another path serves the error list page there" do
    start_imison(name: Dashboard, enabled: false)

    {:ok, view, _html} = live(browser_conn(), "/admin/errors")

    assert has_element?(view, ".nav .nav__link[href='/admin/errors']", "Errors")
    assert has_element?(view, ".panel .empty .empty__title", "No unresolved errors")
  end

  test "the page loads its stylesheet and script from Imison under the mount path" do
    start_imison(name: Dashboard, enabled: false)

    document = browser_conn() |> get("/errors") |> html_response(200) |> LazyHTML.from_document()

    assert [stylesheet] = document |> LazyHTML.query("link[rel=stylesheet]") |> LazyHTML.attribute("href")
    assert [script] = document |> LazyHTML.query("script[src]") |> LazyHTML.attribute("src")
    assert stylesheet =~ ~r{\A/errors/assets/[^/]+/app\.css\z}
    assert script =~ ~r{\A/errors/assets/[^/]+/app\.js\z}
  end

  test "the page makes no third-party requests" do
    start_imison(name: Dashboard, enabled: false)

    document = browser_conn() |> get("/errors") |> html_response(200) |> LazyHTML.from_document()

    urls =
      (document |> LazyHTML.query("[href]") |> LazyHTML.attribute("href")) ++
        (document |> LazyHTML.query("[src]") |> LazyHTML.attribute("src"))

    assert urls != []
    assert Enum.all?(urls, &String.starts_with?(&1, "/errors"))
  end

  test "the dashboard reads the config of the instance named by imison_name" do
    start_imison(name: Imison, enabled: false)

    assert_raise RuntimeError, ~r/No Imison instance named `Imison.Test.Dashboard` is running/, fn ->
      live(browser_conn(), "/errors")
    end
  end
end
