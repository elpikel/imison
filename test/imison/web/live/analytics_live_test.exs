defmodule Imison.Web.AnalyticsLiveTest do
  use Imison.ConnCase, async: false

  import Imison.Test.CaptureHelpers

  alias Imison.Analytics.Pageview
  alias Imison.Test.Dashboard
  alias Imison.Test.Repo

  test "following Analytics in the top bar opens the Analytics tab" do
    start_imison(name: Dashboard, enabled: false, analytics: true)
    conn = sign_in("/errors", "admin", "secret")
    {:ok, list, _html} = live(conn, "/errors")

    {:ok, view, _html} =
      list
      |> element(".nav .nav__link", "Analytics")
      |> render_click()
      |> follow_redirect(conn, "/errors/analytics")

    assert has_element?(view, "h1.page__title", "Analytics")
    assert has_element?(view, ".nav .nav__link[aria-current=page]", "Analytics")
  end

  test "the tab shows visitors, pageviews, bounce rate and visit duration for the last 7 days" do
    start_imison(name: Dashboard, enabled: false, analytics: true)
    visit_started_at = days_ago(2)
    reader = visitor_id()
    store_pageview(%{visitor_id: reader, occurred_at: visit_started_at})
    store_pageview(%{visitor_id: reader, occurred_at: DateTime.shift(visit_started_at, second: 200)})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: visit_started_at})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: days_ago(10)})

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/analytics")

    assert has_element?(view, "#stat-visitors .stat__value", ~r/\A\s*2\s*\z/)
    assert has_element?(view, "#stat-pageviews .stat__value", ~r/\A\s*3\s*\z/)
    assert has_element?(view, "#stat-bounce-rate .stat__value", "50%")
    assert has_element?(view, "#stat-visit-duration .stat__value", "1m 40s")
    assert has_element?(view, ".range__item[aria-current=true]", "7 days")
  end

  test "the chart has one bar per UTC day of the last 7 days, each showing the day and its visitors on hover" do
    start_imison(name: Dashboard, enabled: false, analytics: true)
    store_pageview(%{visitor_id: visitor_id(), occurred_at: DateTime.utc_now()})

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/analytics")

    assert view |> render() |> bars() |> length() == 7
    assert has_element?(view, ".chart__caption", "Visitors per day (UTC)")
    assert has_element?(view, ".chart__slot .chart__tip", "#{day_label(Date.utc_today())} · 1 visitor")
    assert has_element?(view, ".chart__labels", day_label(Date.utc_today()))
  end

  test "a day with one visitor next to a day with thousands still shows a bar, while days without visitors stay empty" do
    start_imison(name: Dashboard, enabled: false, analytics: true)
    busy_day = DateTime.utc_now()

    Repo.insert_all(
      Pageview,
      Enum.map(1..2000, fn _ -> %{path: "/", visitor_id: visitor_id(), occurred_at: busy_day} end)
    )

    store_pageview(%{visitor_id: visitor_id(), occurred_at: days_ago(3)})

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/analytics")

    slots = view |> render() |> chart_slots()
    assert %{tooltip: "#{day_label(Date.add(Date.utc_today(), -3))} · 1 visitor", empty_bar?: false} in slots
    assert %{tooltip: "#{day_label(Date.add(Date.utc_today(), -2))} · 0 visitors", empty_bar?: true} in slots
  end

  test "top pages list each page with its visitors and pageviews" do
    start_imison(name: Dashboard, enabled: false, analytics: true)
    reader = visitor_id()
    store_pageview(%{visitor_id: reader, path: "/pricing", occurred_at: days_ago(1)})
    store_pageview(%{visitor_id: reader, path: "/pricing", occurred_at: days_ago(1)})
    store_pageview(%{visitor_id: visitor_id(), path: "/docs", occurred_at: days_ago(1)})

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/analytics")

    assert top_list_rows(view, "#top-pages") == [["/pricing", "1", "2"], ["/docs", "1", "1"]]
  end

  test "top sources list each source with its visitors and pageviews, and pageviews without a source as Direct / None" do
    start_imison(name: Dashboard, enabled: false, analytics: true)
    store_pageview(%{visitor_id: visitor_id(), source: "news.example.com", occurred_at: days_ago(1)})
    store_pageview(%{visitor_id: visitor_id(), source: "news.example.com", occurred_at: days_ago(1)})
    store_pageview(%{visitor_id: visitor_id(), source: nil, occurred_at: days_ago(1)})

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/analytics")

    assert top_list_rows(view, "#top-sources") == [["news.example.com", "2", "2"], ["Direct / None", "1", "1"]]
  end

  test "picking Today shows today's numbers with hourly bars and keeps the range in the URL" do
    start_imison(name: Dashboard, enabled: false, analytics: true)
    store_pageview(%{visitor_id: visitor_id(), occurred_at: DateTime.utc_now()})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: days_ago(3)})
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/analytics")

    view |> element(".range__item", "Today") |> render_click()

    assert_patch(view, "/errors/analytics?range=today")
    assert has_element?(view, "#stat-visitors .stat__value", ~r/\A\s*1\s*\z/)
    assert has_element?(view, ".range__item[aria-current=true]", "Today")
    assert view |> render() |> bars() |> length() == 24
    assert has_element?(view, ".chart__caption", "Visitors per hour (UTC)")
  end

  test "on today's chart the slot of a recorded pageview shows its UTC hour and visitor count on hover" do
    start_imison(name: Dashboard, enabled: false, analytics: true)
    viewed_at = DateTime.utc_now()
    store_pageview(%{visitor_id: visitor_id(), occurred_at: viewed_at})

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/analytics?range=today")

    hour_range =
      "#{Calendar.strftime(viewed_at, "%H:00")}–#{viewed_at |> DateTime.shift(hour: 1) |> Calendar.strftime("%H:00")} UTC"

    assert has_element?(view, ".chart__slot .chart__tip", "#{hour_range} · 1 visitor")
    assert has_element?(view, ".chart__slot .chart__tip", "· 0 visitors")
  end

  test "picking 30 days shows the last 30 days with daily bars and keeps the range in the URL" do
    start_imison(name: Dashboard, enabled: false, analytics: true)
    store_pageview(%{visitor_id: visitor_id(), occurred_at: days_ago(1)})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: days_ago(20)})
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/analytics")

    view |> element(".range__item", "30 days") |> render_click()

    assert_patch(view, "/errors/analytics?range=30d")
    assert has_element?(view, "#stat-visitors .stat__value", ~r/\A\s*2\s*\z/)
    assert view |> render() |> bars() |> length() == 30
  end

  test "opening the tab with a range in the URL shows that range" do
    start_imison(name: Dashboard, enabled: false, analytics: true)
    store_pageview(%{visitor_id: visitor_id(), occurred_at: days_ago(20)})

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/analytics?range=30d")

    assert has_element?(view, ".range__item[aria-current=true]", "30 days")
    assert has_element?(view, "#stat-visitors .stat__value", ~r/\A\s*1\s*\z/)
  end

  test "an unknown range shows the last 7 days" do
    start_imison(name: Dashboard, enabled: false, analytics: true)
    store_pageview(%{visitor_id: visitor_id(), occurred_at: days_ago(3)})
    store_pageview(%{visitor_id: visitor_id(), occurred_at: days_ago(20)})

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/analytics?range=yesterday")

    assert has_element?(view, ".range__item[aria-current=true]", "7 days")
    assert has_element?(view, "#stat-visitors .stat__value", ~r/\A\s*1\s*\z/)
    assert view |> render() |> bars() |> length() == 7
  end

  test "with no pageviews in the range the tab shows zeros and an empty state instead of the tables" do
    start_imison(name: Dashboard, enabled: false, analytics: true)
    store_pageview(%{visitor_id: visitor_id(), occurred_at: days_ago(20)})

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/analytics")

    assert has_element?(view, "#stat-visitors .stat__value", ~r/\A\s*0\s*\z/)
    assert has_element?(view, "#stat-pageviews .stat__value", ~r/\A\s*0\s*\z/)
    assert has_element?(view, "#stat-bounce-rate .stat__value", "0%")
    assert has_element?(view, "#stat-visit-duration .stat__value", "0s")
    assert has_element?(view, ".empty .empty__title", "No pageviews in this range")
    refute has_element?(view, ".toplist")
  end

  test "a visitor without a session is sent to the login page" do
    start_imison(name: Dashboard, enabled: false, analytics: true)

    assert {:error, {:redirect, %{to: "/errors/login"}}} = live(browser_conn(), "/errors/analytics")
  end

  test "with analytics off the tab says so and how to turn it on" do
    start_imison(name: Dashboard, enabled: false, analytics: false)
    store_pageview(%{visitor_id: visitor_id(), occurred_at: days_ago(1)})

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/analytics")

    assert has_element?(view, ".empty .empty__title", "Analytics is off")
    assert has_element?(view, ".empty", "analytics: true")
    refute has_element?(view, ".stats")
    refute has_element?(view, ".range")
  end

  defp store_pageview(attributes) do
    Repo.insert_all(Pageview, [Map.merge(%{path: "/", source: nil}, attributes)])
  end

  defp visitor_id, do: System.unique_integer([:positive])

  defp days_ago(days), do: DateTime.shift(DateTime.utc_now(), day: -days)

  defp day_label(date), do: Calendar.strftime(date, "%-d %b")

  defp bars(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".chart__bar")
    |> Enum.to_list()
  end

  defp chart_slots(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".chart__slot")
    |> Enum.map(fn slot ->
      tooltip = slot |> LazyHTML.query(".chart__tip") |> LazyHTML.text() |> String.trim()
      empty_bar? = slot |> LazyHTML.query(".chart__bar--empty") |> Enum.any?()
      %{tooltip: tooltip, empty_bar?: empty_bar?}
    end)
  end

  defp top_list_rows(view, list_selector) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#{list_selector} tbody tr")
    |> Enum.map(fn row -> row |> LazyHTML.query("td") |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim())) end)
  end
end
