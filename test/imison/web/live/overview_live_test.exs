defmodule Imison.Web.OverviewLiveTest do
  use Imison.ConnCase, async: false

  import Ecto.Query
  import Imison.Test.CaptureHelpers

  alias Imison.Analytics.Pageview
  alias Imison.Capture
  alias Imison.Errors
  alias Imison.Errors.Error
  alias Imison.Test.Dashboard
  alias Imison.Test.PubSub
  alias Imison.Test.Repo

  @listed_kinds "#overview-errors .error-row .error-row__kind"

  test "the dashboard's root shows the overview with an errors card and an analytics card" do
    start_imison(name: Dashboard, enabled: false)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert has_element?(view, "h1.page__title", "Overview")
    assert has_element?(view, "#overview-errors .section-title", "Errors")
    assert has_element?(view, "#overview-analytics .section-title", "Analytics")
  end

  test "signing in lands on the overview" do
    start_imison(name: Dashboard, enabled: false)
    login_conn = get(browser_conn(), "/errors/login")
    token = login_conn |> html_response(200) |> login_form_token()

    conn =
      login_conn
      |> next_browser_conn()
      |> post("/errors/login", %{"_csrf_token" => token, "username" => "admin", "password" => "secret"})

    {:ok, view, _html} = conn |> next_browser_conn() |> live(redirected_to(conn))

    assert has_element?(view, "h1.page__title", "Overview")
  end

  test "the nav lists Overview, Errors, Analytics and Notifications, marks Overview, and the brand links to the overview" do
    start_imison(name: Dashboard, enabled: false)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert texts(view, ".nav .nav__link") == ["Overview", "Errors", "Analytics", "Notifications"]
    assert has_element?(view, ".nav .nav__link[href='/errors'][aria-current=page]", "Overview")
    assert has_element?(view, ".topbar .brand[href='/errors']", "Imison")
  end

  test "a visitor without a session is sent to the login page" do
    start_imison(name: Dashboard, enabled: false)

    assert {:error, {:redirect, %{to: "/errors/login"}}} = live(browser_conn(), "/errors")
  end

  test "the errors card shows the unresolved count and how many errors were first seen in the last 24 hours" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError", occurred_at: hours_ago(2))
    record(kind: "ArgumentError", occurred_at: hours_ago(30))
    record(kind: "MatchError", occurred_at: hours_ago(40))
    [kind: "Jason.DecodeError", occurred_at: hours_ago(3)] |> record() |> set_status(:resolved)
    [kind: "Postgrex.Error", occurred_at: hours_ago(50)] |> record() |> set_status(:ignored)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert has_element?(view, "#overview-errors #stat-unresolved .stat__value", ~r/\A\s*3\s*\z/)
    assert has_element?(view, "#overview-errors #stat-new-errors .stat__value", ~r/\A\s*2\s*\z/)
  end

  test "the errors card lists the 5 most recently seen unresolved errors, most recent first" do
    start_imison(name: Dashboard, enabled: false)

    for {kind, minutes} <- [A: 60, B: 50, C: 40, D: 30, E: 20, F: 10],
        do: record(kind: "#{kind}Error", occurred_at: minutes_ago(minutes))

    [kind: "ResolvedError", occurred_at: minutes_ago(5)] |> record() |> set_status(:resolved)
    [kind: "IgnoredError", occurred_at: minutes_ago(5)] |> record() |> set_status(:ignored)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert texts(view, @listed_kinds) == ["FError", "EError", "DError", "CError", "BError"]
  end

  test "each listed error shows its kind, message, occurrence count, last seen and heat strip" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError", message: "key :customer_id not found", occurred_at: minutes_ago(20))
    error = record(kind: "KeyError", message: "key :order_id not found", occurred_at: minutes_ago(5))

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert has_element?(view, "#error-#{error.id} .error-row__kind", "KeyError")
    assert has_element?(view, "#error-#{error.id} .error-row__message", "key :order_id not found")
    assert has_element?(view, "#error-#{error.id} .error-row__events", "2")
    assert has_element?(view, "#error-#{error.id} .error-row__seen", "5 min ago")
    assert has_element?(view, "#error-#{error.id} .heat[aria-label='2 events in the last 24 hours']")
  end

  test "clicking a listed error opens its detail page" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError")
    conn = sign_in("/errors", "admin", "secret")
    {:ok, overview, _html} = live(conn, "/errors")

    {:ok, view, _html} =
      overview
      |> element("#error-#{error.id} .error-row__kind")
      |> render_click()
      |> follow_redirect(conn, "/errors/errors/#{error.id}")

    assert has_element?(view, ".error-head__kind", "KeyError")
  end

  test "All errors opens the error list" do
    start_imison(name: Dashboard, enabled: false)
    conn = sign_in("/errors", "admin", "secret")
    {:ok, overview, _html} = live(conn, "/errors")

    {:ok, view, _html} =
      overview
      |> element("#overview-errors a", "All errors")
      |> render_click()
      |> follow_redirect(conn, "/errors/errors")

    assert has_element?(view, "h1.page__title", "Errors")
  end

  test "a newly recorded error appears in the errors card and its counts without a reload" do
    start_imison(name: Dashboard, pubsub: PubSub)
    record(kind: "KeyError", occurred_at: hours_ago(30))
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    capture_and_wait(kind: "ArgumentError", occurred_at: DateTime.utc_now())

    assert texts(view, @listed_kinds) == ["ArgumentError", "KeyError"]
    assert has_element?(view, "#stat-unresolved .stat__value", ~r/\A\s*2\s*\z/)
    assert has_element?(view, "#stat-new-errors .stat__value", ~r/\A\s*1\s*\z/)
  end

  test "without pubsub a refresh shows the errors recorded since the overview opened" do
    start_imison(name: Dashboard, enabled: false)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    record(kind: "KeyError", occurred_at: DateTime.utc_now())
    send(view.pid, :refresh)

    assert texts(view, @listed_kinds) == ["KeyError"]
    assert has_element?(view, ".topbar .live[title='Refreshes from the database every few seconds.']")
  end

  test "with no unresolved errors the errors card says so" do
    start_imison(name: Dashboard, enabled: false)
    [kind: "KeyError"] |> record() |> set_status(:resolved)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert has_element?(view, "#overview-errors .empty__title", "No unresolved errors")
    assert texts(view, @listed_kinds) == []
  end

  test "with analytics on the analytics card shows the last 7 days' visitors, pageviews, bounce rate and a daily chart" do
    start_imison(name: Dashboard, enabled: false, analytics: true)
    reader = visitor_id()
    store_pageview(%{visitor_id: reader, occurred_at: days_ago(2)})
    store_pageview(%{visitor_id: reader, occurred_at: DateTime.shift(days_ago(2), second: 200)})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: days_ago(2)})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: days_ago(10)})

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert has_element?(view, "#overview-analytics #stat-visitors .stat__value", ~r/\A\s*2\s*\z/)
    assert has_element?(view, "#overview-analytics #stat-pageviews .stat__value", ~r/\A\s*3\s*\z/)
    assert has_element?(view, "#overview-analytics #stat-bounce-rate .stat__value", "50%")
    assert has_element?(view, "#overview-analytics .chart__caption", "Visitors per day (UTC)")

    assert view
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#overview-analytics .chart__bar")
           |> Enum.count() == 7
  end

  test "with analytics on the analytics card lists the top 3 pages by visitors" do
    start_imison(name: Dashboard, enabled: false, analytics: true)

    for {path, visitors} <- [{"/", 4}, {"/pricing", 3}, {"/docs", 2}, {"/signup", 1}], _visitor <- 1..visitors do
      store_pageview(%{visitor_id: visitor_id(), path: path, occurred_at: days_ago(1)})
    end

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert texts(view, "#overview-analytics .toplist__name") == ["/", "/pricing", "/docs"]
  end

  test "with analytics on and no pageviews in the last 7 days the analytics card shows zeros and says so" do
    start_imison(name: Dashboard, enabled: false, analytics: true)
    store_pageview(%{visitor_id: visitor_id(), occurred_at: days_ago(10)})

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert has_element?(view, "#overview-analytics #stat-visitors .stat__value", ~r/\A\s*0\s*\z/)
    assert has_element?(view, "#overview-analytics #stat-pageviews .stat__value", ~r/\A\s*0\s*\z/)
    assert has_element?(view, "#overview-analytics #stat-bounce-rate .stat__value", "0%")
    assert has_element?(view, "#overview-analytics .empty__title", "No pageviews in the last 7 days")
    refute has_element?(view, "#overview-analytics .chart")
    refute has_element?(view, "#overview-analytics .toplist")
  end

  test "Full analytics opens the Analytics tab" do
    start_imison(name: Dashboard, enabled: false, analytics: true)
    conn = sign_in("/errors", "admin", "secret")
    {:ok, overview, _html} = live(conn, "/errors")

    {:ok, view, _html} =
      overview
      |> element("#overview-analytics a", "Full analytics")
      |> render_click()
      |> follow_redirect(conn, "/errors/analytics")

    assert has_element?(view, "h1.page__title", "Analytics")
  end

  test "with analytics off the analytics card says so and how to turn it on" do
    start_imison(name: Dashboard, enabled: false, analytics: false)
    store_pageview(%{visitor_id: visitor_id(), occurred_at: days_ago(1)})

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert has_element?(view, "#overview-analytics .empty__title", "Analytics is off")
    assert has_element?(view, "#overview-analytics .empty", "analytics: true")
    refute has_element?(view, "#overview-analytics .stats")
  end

  defp record(overrides) do
    {:ok, error} = Errors.record(Imison.config(Dashboard), occurrence(overrides))
    error
  end

  defp capture_and_wait(overrides) do
    Capture.capture(Dashboard, occurrence(overrides))
    wait_for_worker(Dashboard)
  end

  defp occurrence(overrides) do
    Map.merge(
      %{
        kind: "RuntimeError",
        message: "boom",
        stacktrace: [{Imison.Config, :new, 1, [file: ~c"lib/imison/config.ex", line: 10]}],
        context: %{},
        occurred_at: minutes_ago(1)
      },
      Map.new(overrides)
    )
  end

  defp set_status(%Error{id: error_id} = recorded, status) do
    Error
    |> from(as: :error)
    |> where([error: error], error.id == ^error_id)
    |> Repo.update_all(set: [status: status])

    recorded
  end

  defp store_pageview(attributes) do
    Repo.insert_all(Pageview, [Map.merge(%{path: "/", source: nil}, attributes)])
  end

  defp visitor_id, do: System.unique_integer([:positive])

  defp minutes_ago(minutes), do: DateTime.shift(DateTime.utc_now(), minute: -minutes)

  defp hours_ago(hours), do: DateTime.shift(DateTime.utc_now(), hour: -hours)

  defp days_ago(days), do: DateTime.shift(DateTime.utc_now(), day: -days)

  defp texts(view, selector) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end
end
