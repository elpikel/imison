defmodule Imison.Analytics.TelemetryTest do
  use Imison.ConnCase, async: false

  import ExUnit.CaptureLog
  import Imison.Test.CaptureHelpers

  alias Imison.Analytics.Pageview
  alias Imison.Analytics.Worker
  alias Imison.Capture.Handlers
  alias Imison.Config
  alias Imison.Errors.Error
  alias Imison.Test.Dashboard
  alias Imison.Test.Repo

  @firefox "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.5; rv:132.0) Gecko/20100101 Firefox/132.0"
  @safari "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

  defmodule UnavailableRepo do
    @moduledoc false

    def config, do: []

    def insert_all(_schema, _rows, _opts), do: raise(DBConnection.ConnectionError, "connection not available")
  end

  test "an HTML page load is stored as a pageview with its path, without the query string" do
    name = start_imison(analytics: true)
    before_request = DateTime.utc_now()

    @firefox |> browser() |> get("/pricing?plan=pro#faq") |> html_response(200)

    flush_pageviews(name)
    assert [%Pageview{path: "/pricing", visitor_id: visitor_id, occurred_at: occurred_at}] = Repo.all(Pageview)
    assert is_integer(visitor_id)
    assert DateTime.compare(occurred_at, before_request) != :lt
  end

  test "the referrer of a page load from another site is stored as its source" do
    name = start_imison(analytics: true)

    @firefox
    |> browser()
    |> put_req_header("referer", "https://www.google.com/search?q=imison")
    |> get("/pricing")

    flush_pageviews(name)
    assert [%Pageview{source: "google.com"}] = Repo.all(Pageview)
  end

  test "two page loads from the same browser are the same visitor" do
    name = start_imison(analytics: true)

    @firefox |> browser() |> get("/pricing")
    @firefox |> browser() |> get("/pricing")

    flush_pageviews(name)
    assert [_visitor] = visitors()
  end

  test "page loads from different browsers at the same address are different visitors" do
    name = start_imison(analytics: true)

    @firefox |> browser() |> get("/pricing")
    @safari |> browser() |> get("/pricing")

    flush_pageviews(name)
    assert [_first, _second] = visitors()
  end

  test "with remote_ip_header set, page loads through one proxy for different clients are different visitors" do
    name = start_imison(analytics: true, remote_ip_header: "x-forwarded-for")

    @firefox |> browser() |> put_req_header("x-forwarded-for", "203.0.113.7") |> get("/pricing")
    @firefox |> browser() |> put_req_header("x-forwarded-for", "198.51.100.23") |> get("/pricing")

    flush_pageviews(name)
    assert [_first, _second] = visitors()
  end

  test "with remote_ip_header set, the visitor comes from the first address in the header" do
    name = start_imison(analytics: true, remote_ip_header: "x-forwarded-for")

    @firefox |> browser() |> put_req_header("x-forwarded-for", "203.0.113.7, 10.0.0.1") |> get("/pricing")
    @firefox |> browser() |> put_req_header("x-forwarded-for", " 203.0.113.7 ,10.0.0.2") |> get("/pricing")

    flush_pageviews(name)
    assert [_visitor] = visitors()
  end

  test "with remote_ip_header set, a port on the forwarded address does not change the visitor" do
    name = start_imison(analytics: true, remote_ip_header: "x-forwarded-for")

    @firefox |> browser() |> put_req_header("x-forwarded-for", "203.0.113.7:5678") |> get("/pricing")
    @firefox |> browser() |> put_req_header("x-forwarded-for", "203.0.113.7") |> get("/pricing")
    @firefox |> browser() |> put_req_header("x-forwarded-for", "[2001:db8::1]:5678, 10.0.0.1") |> get("/pricing")
    @firefox |> browser() |> put_req_header("x-forwarded-for", "2001:db8::1") |> get("/pricing")

    flush_pageviews(name)
    assert [_first, _second] = visitors()
  end

  test "remote_ip_header is matched whatever its case" do
    name = start_imison(analytics: true, remote_ip_header: "X-Forwarded-For")

    @firefox |> browser() |> put_req_header("x-forwarded-for", "203.0.113.7") |> get("/pricing")
    @firefox |> browser() |> put_req_header("x-forwarded-for", "198.51.100.23") |> get("/pricing")

    flush_pageviews(name)
    assert [_first, _second] = visitors()
  end

  test "with remote_ip_header set, a page load without that header is counted from its remote address" do
    name = start_imison(analytics: true, remote_ip_header: "x-forwarded-for")

    @firefox |> browser() |> Map.put(:remote_ip, {203, 0, 113, 7}) |> get("/pricing")
    @firefox |> browser() |> Map.put(:remote_ip, {198, 51, 100, 23}) |> get("/pricing")

    @firefox
    |> browser()
    |> put_req_header("x-forwarded-for", "not an address")
    |> Map.put(:remote_ip, {203, 0, 113, 7})
    |> get("/pricing")

    flush_pageviews(name)
    assert [_first, _second] = visitors()
    assert [_first_pageview, _second_pageview, _third_pageview] = Repo.all(Pageview)
  end

  test "without remote_ip_header, page loads from one address with different forwarded addresses are the same visitor" do
    name = start_imison(analytics: true)

    @firefox |> browser() |> put_req_header("x-forwarded-for", "203.0.113.7") |> get("/pricing")
    @firefox |> browser() |> put_req_header("x-forwarded-for", "198.51.100.23") |> get("/pricing")

    flush_pageviews(name)
    assert [_visitor] = visitors()
  end

  test "a page load sets no cookie and its pageview holds neither the IP nor the user agent" do
    name = start_imison(analytics: true)

    conn = @firefox |> browser() |> Map.put(:remote_ip, {203, 0, 113, 7}) |> get("/pricing")

    flush_pageviews(name)
    assert get_resp_header(conn, "set-cookie") == []
    assert [pageview] = Repo.all(Pageview)
    stored_values = pageview |> Map.from_struct() |> Map.values() |> Enum.map_join(" ", &inspect/1)
    refute stored_values =~ "203.0.113.7"
    refute stored_values =~ "Firefox"
  end

  test "an instance started without the analytics option stores no pageview" do
    start_imison()

    @firefox |> browser() |> get("/pricing") |> html_response(200)

    assert Repo.all(Pageview) == []
  end

  test "an instance started without the analytics option starts no analytics worker" do
    name = start_imison()

    assert Imison.Registry.lookup(name, Worker) == nil
  end

  test "a page load answering anything but GET is not stored" do
    name = start_imison(analytics: true)

    build_conn() |> put_req_header("user-agent", @firefox) |> post("/pricing") |> html_response(200)

    flush_pageviews(name)
    assert Repo.all(Pageview) == []
  end

  test "a redirect is not stored" do
    name = start_imison(analytics: true)

    @firefox |> browser() |> get("/plans") |> redirected_to(302)

    flush_pageviews(name)
    assert Repo.all(Pageview) == []
  end

  test "a JSON response is not stored" do
    name = start_imison(analytics: true)

    @firefox |> browser() |> get("/api/status") |> json_response(200)

    flush_pageviews(name)
    assert Repo.all(Pageview) == []
  end

  test "a page load without a user agent is not stored" do
    name = start_imison(analytics: true)

    browser_conn() |> get("/pricing") |> html_response(200)

    flush_pageviews(name)
    assert Repo.all(Pageview) == []
  end

  test "a page load by a crawler is not stored" do
    name = start_imison(analytics: true)

    "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
    |> browser()
    |> get("/pricing")
    |> html_response(200)

    flush_pageviews(name)
    assert Repo.all(Pageview) == []
  end

  test "the dashboard's login page is not stored" do
    start_imison(name: Dashboard, analytics: true)

    @firefox |> browser() |> get("/errors/login") |> html_response(200)

    flush_pageviews(Dashboard)
    assert Repo.all(Pageview) == []
  end

  test "a dashboard page is not stored" do
    start_imison(name: Dashboard, analytics: true)

    "/errors"
    |> sign_in("admin", "secret")
    |> put_req_header("user-agent", @firefox)
    |> get("/errors")
    |> html_response(200)

    flush_pageviews(Dashboard)
    assert Repo.all(Pageview) == []
  end

  test "a page load served by a forwarded router is stored as one pageview" do
    name = start_imison(analytics: true)

    @firefox |> browser() |> get("/shop/catalog") |> html_response(200)

    flush_pageviews(name)
    assert [%Pageview{path: "/shop/catalog"}] = Repo.all(Pageview)
  end

  test "the login page of a dashboard mounted inside a forwarded router is not stored" do
    start_imison(name: Dashboard, analytics: true)

    @firefox |> browser() |> get("/shop/errors/login") |> html_response(200)

    flush_pageviews(Dashboard)
    assert Repo.all(Pageview) == []
  end

  test "a page of a dashboard mounted inside a forwarded router is not stored" do
    start_imison(name: Dashboard, analytics: true)

    "/shop/errors"
    |> sign_in("admin", "secret")
    |> put_req_header("user-agent", @firefox)
    |> get("/shop/errors")
    |> html_response(200)

    flush_pageviews(Dashboard)
    assert Repo.all(Pageview) == []
  end

  test "a page load while the analytics worker's queue is full is dropped and counted, and the page is still served" do
    conf = analytics_config(repo: Repo)
    worker = start_supervised!({Worker, conf: conf, queue_limit: 1, flush_interval: to_timeout(hour: 1)})
    start_supervised!({Handlers, conf: conf})

    :sys.suspend(worker)
    pages = Enum.map(1..3, fn _request -> @firefox |> browser() |> get("/pricing") |> html_response(200) end)
    :sys.resume(worker)

    flush_pageviews(conf.name)
    assert Enum.all?(pages, &(&1 =~ "Pricing"))
    assert Worker.dropped(conf.name) == 2
    assert [%Pageview{}] = Repo.all(Pageview)
  end

  test "a pageview that fails to record is logged under the imison domain, no error is recorded and the worker keeps running" do
    conf = analytics_config(repo: Repo)
    worker = start_supervised!({Worker, conf: %{conf | repo: UnavailableRepo}})
    start_supervised!({Imison.Capture.Worker, conf: conf})
    start_supervised!({Handlers, conf: conf})

    log =
      capture_log([metadata: [:domain]], fn ->
        @firefox |> browser() |> get("/pricing") |> html_response(200)
        flush_pageviews(conf.name)
        @firefox |> browser() |> get("/pricing") |> html_response(200)
        flush_pageviews(conf.name)
        wait_for_recording(conf.name)
      end)

    assert log =~ ~r/domain=elixir\.imison \[error\] Imison failed to record pageviews.*connection not available/s
    assert log |> String.split("Imison failed to record pageviews") |> length() == 3
    assert Repo.all(Error) == []
    assert Process.alive?(worker)
  end

  defp browser(user_agent), do: put_req_header(browser_conn(), "user-agent", user_agent)

  defp visitors, do: Pageview |> Repo.all() |> Enum.map(& &1.visitor_id) |> Enum.uniq()

  defp analytics_config(opts) do
    [name: make_ref(), username: "admin", password: "secret", analytics: true]
    |> Keyword.merge(opts)
    |> Config.new()
  end
end
