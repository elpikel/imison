defmodule Imison.Web.ErrorsLiveTest do
  use Imison.ConnCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  import Imison.Test.CaptureHelpers

  alias Imison.Capture
  alias Imison.Errors
  alias Imison.Errors.Error
  alias Imison.Errors.HourlyCount
  alias Imison.Test.Dashboard
  alias Imison.Test.PubSub
  alias Imison.Test.Repo

  @listed_kinds ".error-row .error-row__kind"
  @flagged_kinds ".error-row__title:has(.flag--regressed) .error-row__kind"

  test "the dashboard mounted with imison_dashboard serves the error list page" do
    start_imison(name: Dashboard, enabled: false)

    {:ok, view, html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert html =~ ~s(<h1 class="page__title">Errors</h1>)
    assert has_element?(view, ".topbar .brand", "Imison")
    assert has_element?(view, ".nav .nav__link[aria-current=page]", "Errors")
    assert has_element?(view, ".panel .empty .empty__title", "No unresolved errors")
  end

  test "the dashboard mounted at another path serves the error list page there" do
    start_imison(name: Dashboard, enabled: false)

    {:ok, view, _html} = live(sign_in("/admin/errors", "admin", "secret"), "/admin/errors")

    assert has_element?(view, ".nav .nav__link[href='/admin/errors']", "Errors")
    assert has_element?(view, ".panel .empty .empty__title", "No unresolved errors")
  end

  test "the page loads its stylesheet and script from Imison under the mount path" do
    start_imison(name: Dashboard, enabled: false)

    document = "/errors" |> sign_in("admin", "secret") |> get("/errors") |> html_response(200) |> LazyHTML.from_document()

    assert [stylesheet] = document |> LazyHTML.query("link[rel=stylesheet]") |> LazyHTML.attribute("href")
    assert [script] = document |> LazyHTML.query("script[src]") |> LazyHTML.attribute("src")
    assert stylesheet =~ ~r{\A/errors/assets/[^/]+/app\.css\z}
    assert script =~ ~r{\A/errors/assets/[^/]+/app\.js\z}
  end

  test "the page makes no third-party requests" do
    start_imison(name: Dashboard, enabled: false)

    document = "/errors" |> sign_in("admin", "secret") |> get("/errors") |> html_response(200) |> LazyHTML.from_document()

    urls =
      (document |> LazyHTML.query("[href]") |> LazyHTML.attribute("href")) ++
        (document |> LazyHTML.query("[src]") |> LazyHTML.attribute("src"))

    assert urls != []
    assert Enum.all?(urls, &String.starts_with?(&1, "/errors"))
  end

  test "a visitor without a session is redirected to the login page" do
    start_imison(name: Dashboard, enabled: false)

    assert {:error, {:redirect, %{to: "/errors/login"}}} = live(browser_conn(), "/errors")
    assert browser_conn() |> get("/errors") |> redirected_to() == "/errors/login"
  end

  test "a visitor without a session is redirected to the login page of the dashboard's mount path" do
    start_imison(name: Dashboard, enabled: false)

    assert {:error, {:redirect, %{to: "/admin/errors/login"}}} = live(browser_conn(), "/admin/errors")
  end

  test "the top bar has a sign-out button" do
    start_imison(name: Dashboard, enabled: false)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert has_element?(view, ".topbar .topbar__end form[method=post][action='/errors/logout'] button", "Sign out")
  end

  test "the dashboard reads the config of the instance named by imison_name" do
    start_imison(name: Imison, enabled: false)

    assert_raise RuntimeError, ~r/No Imison instance named `Imison.Test.Dashboard` is running/, fn ->
      live(browser_conn(), "/errors")
    end
  end

  test "the list shows the unresolved errors, most recently seen first" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError", occurred_at: minutes_ago(30))
    record(kind: "ArgumentError", occurred_at: minutes_ago(5))
    [kind: "MatchError"] |> record() |> set_status(:resolved)
    [kind: "Jason.DecodeError"] |> record() |> set_status(:ignored)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert texts(view, @listed_kinds) == ["ArgumentError", "KeyError"]
    assert has_element?(view, ".tabs__item[aria-current=true]", "Unresolved")
  end

  test "each row shows the kind, message, location, occurrence count and when it was last seen" do
    start_imison(name: Dashboard, enabled: false)

    record(
      kind: "KeyError",
      message: "key :customer_id not found",
      stacktrace: [frame("lib/checkout/invoice_mailer.ex")],
      occurred_at: minutes_ago(20)
    )

    record(
      kind: "KeyError",
      message: "key :order_id not found",
      stacktrace: [frame("lib/checkout/invoice_mailer.ex")],
      occurred_at: minutes_ago(5)
    )

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert has_element?(view, ".error-row .error-row__kind", "KeyError")
    assert has_element?(view, ".error-row .error-row__message", "key :order_id not found")
    assert has_element?(view, ".error-row .error-row__loc", "lib/checkout/invoice_mailer.ex:10")
    assert has_element?(view, ".error-row .error-row__events", "2")
    assert has_element?(view, ".error-row .error-row__seen", "5 min ago")
  end

  test "large occurrence counts are shown with thousands separators" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "DBConnection.ConnectionError")

    Error
    |> from(as: :error)
    |> where([error: error], error.id == ^error.id)
    |> Repo.update_all(set: [occurrence_count: 1_804_250])

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert has_element?(view, ".error-row .error-row__events", "1,804,250")
  end

  test "when an error was last seen reads in seconds, minutes, hours or days" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError", occurred_at: DateTime.utc_now())
    record(kind: "ArgumentError", occurred_at: minutes_ago(3 * 60))
    record(kind: "MatchError", occurred_at: minutes_ago(2 * 24 * 60))

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert has_element?(view, ".error-row .error-row__seen", "just now")
    assert has_element?(view, ".error-row .error-row__seen", "3 h ago")
    assert has_element?(view, ".error-row .error-row__seen", "2 d ago")
  end

  test "the list shows the 100 most recently seen errors and says how many there are in all" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "OldestError", occurred_at: minutes_ago(500))
    for minutes <- 1..100, do: record(kind: "Error#{minutes}", occurred_at: minutes_ago(minutes))

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert texts(view, @listed_kinds) == Enum.map(1..100, &"Error#{&1}")
    assert has_element?(view, ".errors__foot", "The 100 most recently seen of 101 errors")
  end

  test "the list says how many errors it shows" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError")
    record(kind: "ArgumentError")

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert has_element?(view, ".errors__foot", "2 errors")
  end

  test "tabs for Unresolved, Resolved and Ignored show how many errors each holds" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError")
    record(kind: "ArgumentError")
    [kind: "MatchError"] |> record() |> set_status(:resolved)
    [kind: "Jason.DecodeError"] |> record() |> set_status(:ignored)
    [kind: "Postgrex.Error"] |> record() |> set_status(:ignored)
    [kind: "ExitError"] |> record() |> set_status(:ignored)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert tab_counts(view) == %{"Unresolved" => "2", "Resolved" => "1", "Ignored" => "3"}
  end

  test "picking the Resolved tab lists only resolved errors and puts the choice in the URL" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError")
    [kind: "MatchError"] |> record() |> set_status(:resolved)
    [kind: "Jason.DecodeError"] |> record() |> set_status(:ignored)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    view |> element(".tabs__item", "Resolved") |> render_click()

    assert_patch(view, "/errors?status=resolved")
    assert texts(view, @listed_kinds) == ["MatchError"]
    assert has_element?(view, ".tabs__item[aria-current=true]", "Resolved")
  end

  test "picking the Ignored tab lists only ignored errors and puts the choice in the URL" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError")
    [kind: "MatchError"] |> record() |> set_status(:resolved)
    [kind: "Jason.DecodeError"] |> record() |> set_status(:ignored)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    view |> element(".tabs__item", "Ignored") |> render_click()

    assert_patch(view, "/errors?status=ignored")
    assert texts(view, @listed_kinds) == ["Jason.DecodeError"]
  end

  test "opening a URL with a status shows that tab" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError")
    [kind: "Jason.DecodeError"] |> record() |> set_status(:ignored)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?status=ignored")

    assert texts(view, @listed_kinds) == ["Jason.DecodeError"]
    assert has_element?(view, ".tabs__item[aria-current=true]", "Ignored")
  end

  test "picking the Unresolved tab goes back to the dashboard's plain URL" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?status=resolved")

    view |> element(".tabs__item", "Unresolved") |> render_click()

    assert_patch(view, "/errors")
    assert texts(view, @listed_kinds) == ["KeyError"]
  end

  test "searching for text in a message shows only matching errors, case-insensitively, and puts the search in the URL" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "DBConnection.ConnectionError", message: "connection not available, request dropped from queue")
    record(kind: "KeyError", message: "key :customer_id not found")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    view |> form(".toolbar", q: "Request Dropped") |> render_change()

    assert_patch(view, "/errors?q=Request+Dropped")
    assert texts(view, @listed_kinds) == ["DBConnection.ConnectionError"]
  end

  test "searching for text in a kind shows only matching errors" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "Ecto.NoResultsError")
    record(kind: "KeyError")

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?q=noresults")

    assert texts(view, @listed_kinds) == ["Ecto.NoResultsError"]
  end

  test "searching for text in a location shows only matching errors" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError", stacktrace: [frame("lib/checkout/shipping/rates.ex")])
    record(kind: "ArgumentError", stacktrace: [frame("lib/checkout/cart.ex")])

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?q=SHIPPING/rates")

    assert texts(view, @listed_kinds) == ["KeyError"]
  end

  test "the search only shows matching errors in the current tab and the URL keeps both" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError", message: "timeout while charging")
    [kind: "MatchError", message: "timeout while shipping"] |> record() |> set_status(:resolved)
    [kind: "ArgumentError", message: "bad currency"] |> record() |> set_status(:resolved)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?status=resolved")

    view |> form(".toolbar", q: "timeout") |> render_change()

    assert_patch(view, "/errors?status=resolved&q=timeout")
    assert texts(view, @listed_kinds) == ["MatchError"]
  end

  test "the tab counts follow the search" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError", message: "timeout while charging")
    record(kind: "ArgumentError", message: "bad currency")
    [kind: "MatchError", message: "timeout while shipping"] |> record() |> set_status(:resolved)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?q=timeout")

    assert tab_counts(view) == %{"Unresolved" => "1", "Resolved" => "1", "Ignored" => "0"}
  end

  test "switching tabs keeps the search" do
    start_imison(name: Dashboard, enabled: false)
    [kind: "MatchError", message: "timeout while shipping"] |> record() |> set_status(:resolved)
    [kind: "ArgumentError", message: "bad currency"] |> record() |> set_status(:resolved)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?q=timeout")

    view |> element(".tabs__item", "Resolved") |> render_click()

    assert_patch(view, "/errors?status=resolved&q=timeout")
    assert texts(view, @listed_kinds) == ["MatchError"]
  end

  test "a percent sign in the search matches only a literal percent sign" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "File.Error", message: "disk 100% full")
    record(kind: "KeyError", message: "key :customer_id not found")

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?q=%25")

    assert texts(view, @listed_kinds) == ["File.Error"]
  end

  test "an underscore in the search matches only a literal underscore" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError", message: "key :customer_id not found")
    record(kind: "File.Error", message: "disk 100% full")

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?q=_")

    assert texts(view, @listed_kinds) == ["KeyError"]
  end

  test "a backslash in the search matches only a literal backslash" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "File.Error", message: ~S(cannot open C:\tmp\report.csv))
    record(kind: "KeyError", message: "key :customer_id not found")

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?q=%5C")

    assert texts(view, @listed_kinds) == ["File.Error"]
  end

  test "a tab without errors shows the empty state" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError")

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?status=resolved")

    assert texts(view, @listed_kinds) == []
    assert has_element?(view, ".panel .empty .empty__title", "No resolved errors")
  end

  test "a search without matches shows the empty state" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError")

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?q=nothing+like+this")

    assert texts(view, @listed_kinds) == []
    assert has_element?(view, ".panel .empty .empty__title", "No matching errors")
  end

  test "a search given as a list in the URL shows the unfiltered list" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError")

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?q[]=nothing")

    assert texts(view, @listed_kinds) == ["KeyError"]
  end

  test "a search given as a map in the URL shows the unfiltered list" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError")

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?q[text]=nothing")

    assert texts(view, @listed_kinds) == ["KeyError"]
  end

  test "an unresolved error that came back after being resolved shows the Back again flag" do
    start_imison(name: Dashboard, enabled: false)
    [kind: "DBConnection.ConnectionError"] |> record() |> set_status(:resolved)
    record(kind: "DBConnection.ConnectionError")
    record(kind: "KeyError")

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert texts(view, @flagged_kinds) == ["DBConnection.ConnectionError"]
    assert has_element?(view, ".error-row .flag--regressed", "Back again")
  end

  test "an error that came back and was then ignored has no Back again flag" do
    start_imison(name: Dashboard, enabled: false)
    [kind: "DBConnection.ConnectionError"] |> record() |> set_status(:resolved)
    [kind: "DBConnection.ConnectionError"] |> record() |> set_status(:ignored)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?status=ignored")

    assert texts(view, @listed_kinds) == ["DBConnection.ConnectionError"]
    assert texts(view, @flagged_kinds) == []
  end

  test "each row shows 24 hourly cells, oldest first, ending with the current hour" do
    start_imison(name: Dashboard, enabled: false)
    hour = current_hour()
    error = record(kind: "KeyError", occurred_at: start_of(hour))
    record(kind: "KeyError", occurred_at: start_of(DateTime.shift(hour, hour: -23)))

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert heat_levels(view, error) == [
             "4",
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             nil,
             "4"
           ]
  end

  test "empty hours have no level and busier hours get higher levels of the heat scale" do
    start_imison(name: Dashboard, enabled: false)
    hour = current_hour()
    error = record(kind: "KeyError", occurred_at: start_of(DateTime.shift(hour, day: -3)))
    count_in_hour(error, DateTime.shift(hour, hour: -6), 1)
    count_in_hour(error, DateTime.shift(hour, hour: -4), 4)
    count_in_hour(error, DateTime.shift(hour, hour: -2), 6)
    count_in_hour(error, hour, 8)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert heat_levels(view, error) ==
             List.duplicate(nil, 17) ++ ["1", nil, "2", nil, "3", nil, "4"]
  end

  test "the heat strip reads as the number of events in the last 24 hours" do
    start_imison(name: Dashboard, enabled: false)
    hour = current_hour()
    error = record(kind: "KeyError", occurred_at: start_of(DateTime.shift(hour, day: -3)))
    count_in_hour(error, DateTime.shift(hour, hour: -12), 1_200)
    count_in_hour(error, hour, 34)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert has_element?(
             view,
             "#error-#{error.id} .heat.error-row__heat[role=img][aria-label='1,234 events in the last 24 hours']"
           )
  end

  test "a heat strip with one event reads it in the singular" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError", occurred_at: start_of(current_hour()))

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert has_element?(view, "#error-#{error.id} .heat[aria-label='1 event in the last 24 hours']")
  end

  test "counts older than 24 hours are not in the heat strip" do
    start_imison(name: Dashboard, enabled: false)
    hour = current_hour()
    error = record(kind: "KeyError", occurred_at: start_of(DateTime.shift(hour, day: -1)))
    count_in_hour(error, DateTime.shift(hour, hour: -30), 5)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert heat_levels(view, error) == List.duplicate(nil, 24)
    assert has_element?(view, "#error-#{error.id} .heat[aria-label='0 events in the last 24 hours']")
  end

  test "a newly recorded error appears in the open list without a reload" do
    start_imison(name: Dashboard, pubsub: PubSub)
    record(kind: "KeyError")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    capture_and_wait(kind: "ArgumentError", occurred_at: DateTime.utc_now())

    assert texts(view, @listed_kinds) == ["ArgumentError", "KeyError"]
    assert has_element?(view, ".errors__foot", "2 errors")
  end

  test "another occurrence of a listed error updates its count, last seen and heat strip without a reload" do
    start_imison(name: Dashboard, pubsub: PubSub)
    current_hour()
    error = record(kind: "KeyError", occurred_at: minutes_ago(3 * 60))
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    assert List.last(heat_levels(view, error)) == nil

    capture_and_wait(kind: "KeyError", occurred_at: DateTime.utc_now())

    assert has_element?(view, "#error-#{error.id} .error-row__events", "2")
    assert has_element?(view, "#error-#{error.id} .error-row__seen", "just now")
    assert List.last(heat_levels(view, error)) == "4"
    assert has_element?(view, "#error-#{error.id} .heat[aria-label='2 events in the last 24 hours']")
  end

  test "the tab counts update as errors are recorded" do
    start_imison(name: Dashboard, pubsub: PubSub)
    [kind: "MatchError"] |> record() |> set_status(:resolved)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    assert tab_counts(view) == %{"Unresolved" => "0", "Resolved" => "1", "Ignored" => "0"}

    capture_and_wait(kind: "MatchError", occurred_at: DateTime.utc_now())

    assert tab_counts(view) == %{"Unresolved" => "1", "Resolved" => "0", "Ignored" => "0"}
  end

  test "an error recorded right after a live update still appears, within a second" do
    start_imison(name: Dashboard, pubsub: PubSub)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    capture_and_wait(kind: "KeyError", occurred_at: DateTime.utc_now())
    assert texts(view, @listed_kinds) == ["KeyError"]

    capture_and_wait(kind: "ArgumentError", occurred_at: DateTime.utc_now())

    assert listed_within?(view, "ArgumentError", 2_000)
  end

  test "with pubsub configured, the connected list shows the live indicator in the top bar" do
    start_imison(name: Dashboard, pubsub: PubSub, enabled: false)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    assert has_element?(view, ".topbar .topbar__end .live .live__dot")
    assert has_element?(view, ".topbar .topbar__end .live", "Live")
  end

  test "the page as first served, before it connects, shows no live indicator" do
    start_imison(name: Dashboard, pubsub: PubSub, enabled: false)

    document = "/errors" |> sign_in("admin", "secret") |> get("/errors") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query(".topbar") |> Enum.count() == 1
    assert document |> LazyHTML.query(".live") |> Enum.empty?()
  end

  test "without pubsub the list shows no live indicator and lists recorded errors on reload" do
    start_imison(name: Dashboard)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    capture_and_wait(kind: "KeyError", occurred_at: DateTime.utc_now())

    refute has_element?(view, ".live")
    {:ok, reloaded_view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    assert texts(reloaded_view, @listed_kinds) == ["KeyError"]
  end

  test "with no PubSub running under the configured name, the connected list still serves errors, without the live indicator, and logs the failure" do
    start_imison(name: Dashboard, pubsub: Imison.Test.MissingPubSub, enabled: false)
    record(kind: "KeyError")

    {result, log} =
      with_log([metadata: [:domain]], fn -> live(sign_in("/errors", "admin", "secret"), "/errors") end)

    assert {:ok, view, _html} = result
    assert texts(view, @listed_kinds) == ["KeyError"]
    refute has_element?(view, ".live")
    assert log =~ ~r/domain=elixir\.imison \[error\] Imison failed to subscribe to recorded errors/
  end

  test "resolving two selected errors from the bulk bar stores them as resolved, takes them off the tab and updates the counts" do
    start_imison(name: Dashboard, enabled: false)
    first = record(kind: "KeyError")
    second = record(kind: "ArgumentError")
    third = record(kind: "MatchError")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    tick(view, first)
    tick(view, second)

    view |> element(".bulkbar .btn", "Resolve") |> render_click()

    assert %Error{status: :resolved} = Repo.get!(Error, first.id)
    assert %Error{status: :resolved} = Repo.get!(Error, second.id)
    assert %Error{status: :unresolved} = Repo.get!(Error, third.id)
    assert texts(view, @listed_kinds) == ["MatchError"]
    assert tab_counts(view) == %{"Unresolved" => "1", "Resolved" => "2", "Ignored" => "0"}
  end

  test "ignoring selected errors from the bulk bar stores them as ignored" do
    start_imison(name: Dashboard, enabled: false)
    first = record(kind: "KeyError")
    second = record(kind: "ArgumentError")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    tick(view, first)
    tick(view, second)

    view |> element(".bulkbar .btn", "Ignore") |> render_click()

    assert %Error{status: :ignored} = Repo.get!(Error, first.id)
    assert %Error{status: :ignored} = Repo.get!(Error, second.id)
  end

  test "marking selected resolved errors unresolved from the bulk bar stores them as unresolved" do
    start_imison(name: Dashboard, enabled: false)
    error = [kind: "KeyError"] |> record() |> set_status(:resolved)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?status=resolved")
    tick(view, error)

    view |> element(".bulkbar .btn", "Mark unresolved") |> render_click()

    assert %Error{status: :unresolved} = Repo.get!(Error, error.id)
  end

  test "marking selected ignored errors unresolved from the bulk bar stores them as unresolved" do
    start_imison(name: Dashboard, enabled: false)
    error = [kind: "KeyError"] |> record() |> set_status(:ignored)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?status=ignored")
    tick(view, error)

    view |> element(".bulkbar .btn", "Mark unresolved") |> render_click()

    assert %Error{status: :unresolved} = Repo.get!(Error, error.id)
  end

  test "the bulk bar offers the actions that move errors off the current tab" do
    start_imison(name: Dashboard, enabled: false)
    unresolved = record(kind: "KeyError")
    resolved = [kind: "MatchError"] |> record() |> set_status(:resolved)
    ignored = [kind: "ArgumentError"] |> record() |> set_status(:ignored)
    {:ok, unresolved_view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    {:ok, resolved_view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?status=resolved")
    {:ok, ignored_view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors?status=ignored")

    tick(unresolved_view, unresolved)
    tick(resolved_view, resolved)
    tick(ignored_view, ignored)

    assert texts(unresolved_view, ".bulkbar .btn") == ["Resolve", "Ignore"]
    assert texts(resolved_view, ".bulkbar .btn") == ["Mark unresolved", "Ignore"]
    assert texts(ignored_view, ".bulkbar .btn") == ["Mark unresolved", "Resolve"]
  end

  test "ticking Select all selects every listed row and the bulk bar shows the count" do
    start_imison(name: Dashboard, enabled: false)
    first = record(kind: "KeyError")
    second = record(kind: "ArgumentError")
    third = record(kind: "MatchError")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    view |> element(".errors__head .checkbox") |> render_click()

    assert has_element?(view, ".bulkbar", "3 selected")
    assert Enum.all?([first, second, third], &has_element?(view, "#error-#{&1.id} .error-row__check[checked]"))
  end

  test "unticking Select all clears the selection" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError")
    record(kind: "ArgumentError")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    view |> element(".errors__head .checkbox") |> render_click()

    view |> element(".errors__head .checkbox") |> render_click()

    refute has_element?(view, ".bulkbar")
    refute has_element?(view, ".error-row__check[checked]")
  end

  test "the bulk bar shows how many rows are selected" do
    start_imison(name: Dashboard, enabled: false)
    first = record(kind: "KeyError")
    record(kind: "ArgumentError")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    tick(view, first)

    assert has_element?(view, ".bulkbar", "1 selected")
  end

  test "with no row selected the bulk bar is hidden" do
    start_imison(name: Dashboard, enabled: false)
    record(kind: "KeyError")

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    refute has_element?(view, ".bulkbar")
  end

  test "unticking the only selected row hides the bulk bar" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    tick(view, error)

    tick(view, error)

    refute has_element?(view, ".bulkbar")
  end

  test "switching tabs clears the selection" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    tick(view, error)

    view |> element(".tabs__item", "Resolved") |> render_click()
    view |> element(".tabs__item", "Unresolved") |> render_click()

    refute has_element?(view, ".bulkbar")
  end

  test "searching clears the selection" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    tick(view, error)

    view |> form(".toolbar", q: "Key") |> render_change()

    refute has_element?(view, ".bulkbar")
  end

  test "after a bulk action nothing stays selected" do
    start_imison(name: Dashboard, enabled: false)
    first = record(kind: "KeyError")
    record(kind: "ArgumentError")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    tick(view, first)

    view |> element(".bulkbar .btn", "Resolve") |> render_click()

    refute has_element?(view, ".bulkbar")
  end

  test "another open list reloads its rows and counts when errors change status" do
    start_imison(name: Dashboard, pubsub: PubSub, enabled: false)
    first = record(kind: "KeyError")
    record(kind: "ArgumentError")
    {:ok, acting_view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    {:ok, watching_view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    tick(acting_view, first)

    acting_view |> element(".bulkbar .btn", "Resolve") |> render_click()

    assert texts(watching_view, @listed_kinds) == ["ArgumentError"]
    assert tab_counts(watching_view) == %{"Unresolved" => "1", "Resolved" => "1", "Ignored" => "0"}
  end

  test "a selected row that another list moves off the tab is no longer selected" do
    start_imison(name: Dashboard, pubsub: PubSub, enabled: false)
    first = record(kind: "KeyError")
    record(kind: "ArgumentError")
    {:ok, acting_view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    {:ok, watching_view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    tick(acting_view, first)
    tick(watching_view, first)

    acting_view |> element(".bulkbar .btn", "Resolve") |> render_click()

    refute has_element?(watching_view, ".bulkbar")
  end

  test "a status event with an unknown status changes nothing and the page keeps working" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")
    tick(view, error)

    render_click(view, "set_status", %{"status" => "deleted"})
    render_click(view, "set_status", %{})

    assert %Error{status: :unresolved} = Repo.get!(Error, error.id)
    assert texts(view, @listed_kinds) == ["KeyError"]
  end

  test "selecting ids that are not listed error ids selects nothing, so a bulk action changes nothing" do
    start_imison(name: Dashboard, enabled: false)
    listed = record(kind: "KeyError")
    unlisted = [kind: "MatchError"] |> record() |> set_status(:ignored)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors")

    render_click(view, "toggle_selection", %{"id" => "abc"})
    render_click(view, "toggle_selection", %{"id" => Integer.to_string(unlisted.id)})
    render_click(view, "toggle_selection", %{})
    render_click(view, "set_status", %{"status" => "resolved"})

    refute has_element?(view, ".bulkbar")
    assert %Error{status: :unresolved} = Repo.get!(Error, listed.id)
    assert %Error{status: :ignored} = Repo.get!(Error, unlisted.id)
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
        stacktrace: [frame("lib/imison/config.ex")],
        context: %{},
        occurred_at: minutes_ago(1)
      },
      Map.new(overrides)
    )
  end

  defp listed_within?(view, kind, milliseconds) do
    deadline = System.monotonic_time(:millisecond) + milliseconds
    listed_before?(view, kind, deadline)
  end

  defp listed_before?(view, kind, deadline) do
    cond do
      kind in texts(view, @listed_kinds) ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(50)
        listed_before?(view, kind, deadline)
    end
  end

  defp frame(file), do: {Imison.Config, :new, 1, [file: String.to_charlist(file), line: 10]}

  defp minutes_ago(minutes), do: DateTime.shift(DateTime.utc_now(), minute: -minutes)

  defp current_hour do
    now = DateTime.utc_now()
    hour = %{now | minute: 0, second: 0, microsecond: {0, 0}}
    next_hour = DateTime.shift(hour, hour: 1)
    milliseconds_left_in_hour = DateTime.diff(next_hour, now, :millisecond)

    if milliseconds_left_in_hour < 10_000 do
      Process.sleep(milliseconds_left_in_hour)
      current_hour()
    else
      hour
    end
  end

  defp start_of(hour), do: %{hour | microsecond: {0, 6}}

  defp count_in_hour(%Error{id: error_id}, hour, count) do
    Repo.insert!(%HourlyCount{error_id: error_id, hour: hour, count: count})
  end

  defp heat_levels(view, %Error{id: error_id}) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#error-#{error_id} .heat i")
    |> Enum.map(&(&1 |> LazyHTML.attribute("data-l") |> List.first()))
  end

  defp set_status(%Error{id: error_id} = recorded, status) do
    Error
    |> from(as: :error)
    |> where([error: error], error.id == ^error_id)
    |> Repo.update_all(set: [status: status])

    recorded
  end

  defp tick(view, %Error{id: error_id}) do
    view |> element("#error-#{error_id} .error-row__check") |> render_click()
  end

  defp texts(view, selector) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  defp tab_counts(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".tabs__item")
    |> Map.new(fn tab ->
      count = tab |> LazyHTML.query(".tabs__count") |> LazyHTML.text()
      label = tab |> LazyHTML.text() |> String.replace_suffix(count, "") |> String.trim()
      {label, count}
    end)
  end
end
