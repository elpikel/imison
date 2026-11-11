defmodule Imison.Web.AssetsTest do
  use Imison.ConnCase, async: false

  import Imison.Test.CaptureHelpers

  alias Imison.Test.Dashboard

  test "the stylesheet is served under the mount path with a long cache lifetime" do
    start_imison(name: Dashboard, enabled: false)
    page = browser_conn() |> get("/errors") |> html_response(200)

    conn = get(browser_conn(), page_asset(page, "link[rel=stylesheet]", "href"))

    assert response(conn, 200) == File.read!("priv/static/app.css")
    assert response_content_type(conn, :css) =~ "text/css"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
  end

  test "the fonts the stylesheet links to are served next to it" do
    start_imison(name: Dashboard, enabled: false)
    page = browser_conn() |> get("/errors") |> html_response(200)
    stylesheet = page_asset(page, "link[rel=stylesheet]", "href")
    stylesheet_body = browser_conn() |> get(stylesheet) |> response(200)

    font = stylesheet |> font_urls(stylesheet_body) |> List.first()
    conn = get(browser_conn(), font)

    assert font =~ ~r{\A/errors/assets/[^/]+/fonts/.+\.woff2\z}
    assert response(conn, 200) == File.read!(Path.join("priv/static/fonts", Path.basename(font)))
    assert get_resp_header(conn, "content-type") == ["font/woff2"]
  end

  test "every font the stylesheet links to is served" do
    start_imison(name: Dashboard, enabled: false)
    page = browser_conn() |> get("/errors") |> html_response(200)
    stylesheet = page_asset(page, "link[rel=stylesheet]", "href")
    stylesheet_body = browser_conn() |> get(stylesheet) |> response(200)

    statuses =
      stylesheet |> font_urls(stylesheet_body) |> Enum.map(&(browser_conn() |> get(&1) |> Map.fetch!(:status)))

    assert statuses != []
    assert Enum.all?(statuses, &(&1 == 200))
  end

  test "the script that connects the LiveView socket is served under the mount path" do
    start_imison(name: Dashboard, enabled: false)
    page = browser_conn() |> get("/errors") |> html_response(200)

    conn = get(browser_conn(), page_asset(page, "script[src]", "src"))

    assert response(conn, 200) =~ "new LiveView.LiveSocket("
    assert response_content_type(conn, :js) =~ "text/javascript"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
  end

  test "the assets are served under any mount path" do
    start_imison(name: Dashboard, enabled: false)
    page = browser_conn() |> get("/admin/errors") |> html_response(200)
    stylesheet = page_asset(page, "link[rel=stylesheet]", "href")
    script = page_asset(page, "script[src]", "src")
    stylesheet_body = browser_conn() |> get(stylesheet) |> response(200)
    font = stylesheet |> font_urls(stylesheet_body) |> List.first()

    assert stylesheet =~ ~r{\A/admin/errors/assets/}
    assert stylesheet_body =~ "@font-face"
    assert browser_conn() |> get(script) |> response(200) =~ "LiveSocket"
    assert browser_conn() |> get(font) |> response(200) == File.read!(Path.join("priv/static/fonts", Path.basename(font)))
  end

  test "an asset under an outdated digest is not found" do
    start_imison(name: Dashboard, enabled: false)
    page = browser_conn() |> get("/errors") |> html_response(200)
    stylesheet = page_asset(page, "link[rel=stylesheet]", "href")

    outdated = String.replace(stylesheet, ~r{/assets/[^/]+/}, "/assets/outdated/")

    assert browser_conn() |> get(outdated) |> response(404)
  end

  test "an unknown asset is not found" do
    start_imison(name: Dashboard, enabled: false)
    page = browser_conn() |> get("/errors") |> html_response(200)
    stylesheet = page_asset(page, "link[rel=stylesheet]", "href")

    unknown = String.replace(stylesheet, "app.css", "fonts/unknown.woff2")

    assert browser_conn() |> get(unknown) |> response(404)
  end

  defp page_asset(page, selector, attribute) do
    [url] =
      page
      |> LazyHTML.from_document()
      |> LazyHTML.query(selector)
      |> LazyHTML.attribute(attribute)

    url
  end

  defp font_urls(stylesheet, stylesheet_body) do
    ~r/url\("([^"]+)"\)/
    |> Regex.scan(stylesheet_body, capture: :all_but_first)
    |> Enum.map(fn [relative] ->
      "http://localhost" |> URI.merge(stylesheet) |> URI.merge(relative) |> Map.fetch!(:path)
    end)
  end
end
