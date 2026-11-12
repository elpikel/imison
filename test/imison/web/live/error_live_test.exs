defmodule Imison.Web.ErrorLiveTest do
  use Imison.ConnCase, async: false

  import Ecto.Query
  import Imison.Test.CaptureHelpers

  alias Imison.Capture
  alias Imison.Errors
  alias Imison.Errors.Error
  alias Imison.Errors.Occurrence
  alias Imison.Test.Dashboard
  alias Imison.Test.Repo

  test "clicking an error's kind in the list opens its detail page" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError", message: "key :customer_id not found")
    conn = sign_in("/errors", "admin", "secret")
    {:ok, list, _html} = live(conn, "/errors")

    {:ok, detail, _html} =
      list
      |> element(".error-row .error-row__kind", "KeyError")
      |> render_click()
      |> follow_redirect(conn, "/errors/errors/#{error.id}")

    assert has_element?(detail, ".error-head__kind", "KeyError")
    assert has_element?(detail, ".error-head__message", "key :customer_id not found")
  end

  test "the detail page shows the error's kind, message, location, status, occurrence count, first and last seen" do
    start_imison(name: Dashboard, enabled: false)
    stacktrace = [{Checkout.Payments, :normalize_currency, 1, [file: ~c"lib/checkout/payments.ex", line: 140]}]
    record(kind: "FunctionClauseError", stacktrace: stacktrace, occurred_at: ~U[2026-11-11 13:05:00.000000Z])

    error =
      record(
        kind: "FunctionClauseError",
        message: "no function clause matching in Checkout.Payments.normalize_currency/1",
        stacktrace: stacktrace,
        occurred_at: ~U[2026-11-11 14:32:07.000000Z]
      )

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    assert has_element?(view, ".error-head__kind", "FunctionClauseError")

    assert has_element?(
             view,
             ".error-head__message",
             "no function clause matching in Checkout.Payments.normalize_currency/1"
           )

    assert has_element?(
             view,
             ".error-head__location",
             "Checkout.Payments.normalize_currency/1 (lib/checkout/payments.ex:140)"
           )

    assert has_element?(view, ".error-head__meta .flag--unresolved", "Unresolved")
    assert rail_value(view, "Events") == "2"
    assert rail_value(view, "First seen") == "11 Nov 2026, 13:05:00 UTC"
    assert rail_value(view, "Last seen") == "11 Nov 2026, 14:32:07 UTC"
  end

  test "the detail page shows a resolved error's status" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "MatchError")
    set_status(error, :resolved)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    assert has_element?(view, ".error-head__meta .flag--resolved", "Resolved")
  end

  test "the stack trace shows the latest occurrence's frames, one by one, with module, function/arity and file:line" do
    start_imison(name: Dashboard, enabled: false)
    failing_frame = {Checkout.Payments, :normalize_currency, 1, [file: ~c"lib/checkout/payments.ex", line: 140]}

    error =
      record(
        kind: "FunctionClauseError",
        stacktrace: [
          failing_frame,
          {Checkout.Orders, :place, 2, [file: ~c"lib/checkout/orders.ex", line: 54]},
          {:erlang, :apply, 2, []}
        ],
        occurred_at: minutes_ago(1)
      )

    record(
      kind: "FunctionClauseError",
      stacktrace: [failing_frame, {Checkout.Refunds, :issue, 3, [file: ~c"lib/checkout/refunds.ex", line: 12]}],
      occurred_at: minutes_ago(30)
    )

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    assert frames(view) == [
             %{function: "Checkout.Payments.normalize_currency/1", location: "lib/checkout/payments.ex:140"},
             %{function: "Checkout.Orders.place/2", location: "lib/checkout/orders.ex:54"},
             %{function: ":erlang.apply/2", location: ""}
           ]
  end

  test "frames from the host app's modules are shown open as application frames and dependency frames are muted" do
    start_imison(name: Dashboard, enabled: false)

    error =
      record(
        stacktrace: [
          {Imison.Config, :new, 1, [file: ~c"lib/imison/config.ex", line: 10]},
          {Ecto.Repo, :insert, 2, [file: ~c"lib/ecto/repo.ex", line: 7]},
          {Imison.Migration, :up, 1, [file: ~c"lib/imison/migration.ex", line: 20]},
          {:erlang, :apply, 2, []}
        ]
      )

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    assert frame_markings(view) == [
             %{function: "Imison.Config.new/1", style: "frame--app", open: true},
             %{function: "Ecto.Repo.insert/2", style: "frame--dep", open: false},
             %{function: "Imison.Migration.up/1", style: "frame--app", open: true},
             %{function: ":erlang.apply/2", style: "frame--dep", open: false}
           ]

    assert has_element?(view, ".panel__head .muted", "The teal edge marks frames in your code")
  end

  test "a frame marked as an application frame when captured keeps its marking after its module is renamed" do
    start_imison(name: Dashboard, enabled: false)
    error = record(stacktrace: [{Imison.Config, :new, 1, [file: ~c"lib/imison/config.ex", line: 10]}])

    set_stored_frames(error, [
      %{
        "module" => "Imison.RenamedSinceCapture",
        "function" => "new",
        "arity" => 1,
        "file" => "lib/imison/config.ex",
        "line" => 10,
        "application" => true
      }
    ])

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    assert frame_markings(view) == [%{function: "Imison.RenamedSinceCapture.new/1", style: "frame--app", open: true}]
  end

  test "a frame stored before frames were marked is shown as a dependency frame" do
    start_imison(name: Dashboard, enabled: false)
    error = record(stacktrace: [{Imison.Config, :new, 1, [file: ~c"lib/imison/config.ex", line: 10]}])

    set_stored_frames(error, [
      %{"module" => "Imison.Config", "function" => "new", "arity" => 1, "file" => "lib/imison/config.ex", "line" => 10}
    ])

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    assert frame_markings(view) == [%{function: "Imison.Config.new/1", style: "frame--dep", open: false}]
    refute has_element?(view, ".panel__head .muted", "The teal edge marks frames in your code")
  end

  test "the detail page shows the request, logger metadata and runtime of the latest occurrence" do
    start_imison(name: Dashboard, release: "2.14.3")
    {exception, stacktrace} = raised("no currency")

    event =
      Capture.event(%{kind: :error, reason: exception, stacktrace: stacktrace}, %{
        request: %{
          method: "POST",
          path: "/api/orders",
          params: %{"cart_id" => "c_81f3", "card" => "4242"},
          headers: %{"user-agent" => "CheckoutApp/5.2"}
        },
        metadata: %{request_id: "GHk3x0Zq1mE7tQwAAB2C", user_id: 48_213}
      })

    Capture.capture(Dashboard, event)
    wait_for_worker(Dashboard)
    error = error_with_message("no currency")

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    assert panel(view, "Request") == %{
             "Method and path" => "POST /api/orders",
             "Params" => ~s(%{"card" => "4242", "cart_id" => "c_81f3"}),
             "Headers" => ~s(%{"user-agent" => "CheckoutApp/5.2"})
           }

    assert panel(view, "Logger metadata") == %{"request_id" => "GHk3x0Zq1mE7tQwAAB2C", "user_id" => "48213"}
    assert panel(view, "Runtime") == %{"Node" => Atom.to_string(node()), "Release" => "2.14.3"}
  end

  test "a request captured from a failed Phoenix request is shown in the Request panel, without a metadata panel" do
    start_imison(name: Dashboard)
    message = unique_message()
    {exception, stacktrace} = raised(message)

    conn =
      :post
      |> Plug.Test.conn("/orders", %{"order" => %{"id" => "7"}})
      |> Plug.Conn.put_req_header("user-agent", "curl/8.0")

    :telemetry.execute([:phoenix, :router_dispatch, :exception], %{duration: 1_000}, %{
      conn: conn,
      kind: :error,
      reason: exception,
      stacktrace: stacktrace
    })

    wait_for_worker(Dashboard)
    error = error_with_message(message)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    assert %{"Method and path" => "POST /orders", "Params" => ~s(%{"order" => %{"id" => "7"}})} =
             panel(view, "Request")

    assert panel(view, "Request")["Headers"] =~ ~s("user-agent" => "curl/8.0")
    assert panel_titles(view) == ["Stack trace", "Request", "Runtime"]
  end

  test "an occurrence without a request leaves the Request panel out" do
    start_imison(name: Dashboard)
    message = unique_message()
    {exception, stacktrace} = raised(message)

    Capture.capture(
      Dashboard,
      Capture.event(%{kind: :error, reason: exception, stacktrace: stacktrace}, %{metadata: %{order_id: 7}})
    )

    wait_for_worker(Dashboard)
    error = error_with_message(message)

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    assert panel_titles(view) == ["Stack trace", "Logger metadata", "Runtime"]
    assert panel(view, "Logger metadata") == %{"order_id" => "7"}
  end

  test "an occurrence without context, release or stack trace shows only the summary" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "exit", stacktrace: [], context: %{})

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    assert has_element?(view, ".error-head__kind", "exit")
    assert panel_titles(view) == []
  end

  test "an error whose occurrences were all pruned shows its summary without stack trace or context panels" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError", context: %{"metadata" => %{"order_id" => 7}}, occurred_at: days_ago(40))
    Errors.prune(Imison.config(Dashboard), DateTime.utc_now())

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    assert has_element?(view, ".error-head__kind", "KeyError")
    assert has_element?(view, ".error-head__message", "boom")
    assert panel_titles(view) == []
  end

  test "context values are shown as text, never as markup" do
    start_imison(name: Dashboard, enabled: false)

    error =
      record(
        kind: "RuntimeError",
        message: "<b>bold</b>",
        context: %{"metadata" => %{"note" => "<script>alert(1)</script>"}}
      )

    {:ok, view, html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    refute html =~ "<script>alert(1)</script>"
    refute html =~ "<b>bold</b>"
    assert has_element?(view, ".error-head__message", "<b>bold</b>")
    assert panel(view, "Logger metadata") == %{"note" => "<script>alert(1)</script>"}
  end

  test "opening an error that doesn't exist sends the developer back to the list with a message" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError")
    Repo.delete!(error)
    conn = sign_in("/errors", "admin", "secret")

    {:ok, view, _html} = conn |> live("/errors/errors/#{error.id}") |> follow_redirect(conn, "/errors")

    assert has_element?(view, ".flash--error[role=alert]", "That error doesn't exist. It may have been deleted.")
    assert has_element?(view, ".page__title", "Errors")
  end

  test "opening an error with an id that isn't a number sends the developer back to the list with a message" do
    start_imison(name: Dashboard, enabled: false)
    conn = sign_in("/errors", "admin", "secret")

    for id <- ["abc", "12abc", "99999999999999999999"] do
      {:ok, view, _html} = conn |> live("/errors/errors/#{id}") |> follow_redirect(conn, "/errors")

      assert has_element?(view, ".flash--error", "That error doesn't exist. It may have been deleted.")
    end
  end

  test "a visitor without a session who opens a detail page is redirected to the login page" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError")

    assert {:error, {:redirect, %{to: "/errors/login"}}} = live(browser_conn(), "/errors/errors/#{error.id}")
    assert browser_conn() |> get("/errors/errors/#{error.id}") |> redirected_to() == "/errors/login"
  end

  test "resolving an unresolved error from its detail page stores it as resolved and shows it as resolved" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    view |> element(".rail .btn--primary", "Resolve") |> render_click()

    assert %Error{status: :resolved} = Repo.get!(Error, error.id)
    assert has_element?(view, ".error-head__meta .flag--resolved", "Resolved")
  end

  test "ignoring an unresolved error from its detail page stores it as ignored and shows it as ignored" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    view |> element(".rail .btn", "Ignore") |> render_click()

    assert %Error{status: :ignored} = Repo.get!(Error, error.id)
    assert has_element?(view, ".error-head__meta .flag--off", "Ignored")
  end

  test "marking a resolved error unresolved from its detail page stores it as unresolved" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError")
    set_status(error, :resolved)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    view |> element(".rail .btn", "Mark unresolved") |> render_click()

    assert %Error{status: :unresolved} = Repo.get!(Error, error.id)
    assert has_element?(view, ".error-head__meta .flag--unresolved", "Unresolved")
  end

  test "marking an ignored error unresolved from its detail page stores it as unresolved" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError")
    set_status(error, :ignored)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    view |> element(".rail .btn", "Mark unresolved") |> render_click()

    assert %Error{status: :unresolved} = Repo.get!(Error, error.id)
  end

  test "an unresolved error's detail page offers Resolve and Ignore, and a resolved one only Mark unresolved" do
    start_imison(name: Dashboard, enabled: false)
    unresolved = record(kind: "KeyError")
    resolved = record(kind: "MatchError")
    set_status(resolved, :resolved)

    {:ok, unresolved_view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{unresolved.id}")
    {:ok, resolved_view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{resolved.id}")

    assert status_buttons(unresolved_view) == ["Resolve", "Ignore"]
    assert status_buttons(resolved_view) == ["Mark unresolved"]
  end

  test "a status event with an unknown status changes nothing and the page keeps working" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError")
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    render_click(view, "set_status", %{"status" => "deleted"})
    render_click(view, "set_status", %{})

    assert %Error{status: :unresolved} = Repo.get!(Error, error.id)
    assert has_element?(view, ".error-head__meta .flag--unresolved", "Unresolved")
  end

  test "the detail page opens on the latest of three occurrences, with its time, stack trace and context" do
    start_imison(name: Dashboard, enabled: false)
    error = record_three_attempts()

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    assert has_element?(view, ".occurrence-nav__when strong", "Occurrence 3 of 3")
    assert has_element?(view, ".occurrence-nav__when .muted", "11 Nov 2026, 12:00:00 UTC")
    assert frames(view) == [%{function: "Checkout.Payments.charge/1", location: "lib/checkout/payments.ex:103"}]
    assert panel(view, "Logger metadata") == %{"attempt" => "3"}
  end

  test "clicking Older shows the previous occurrence and names it in the URL" do
    start_imison(name: Dashboard, enabled: false)
    error = record_three_attempts()
    [_oldest_id, middle_id, _latest_id] = occurrence_ids_oldest_first(error)
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    view |> element(".occurrence-nav a", "Older") |> render_click()

    assert_patch(view, "/errors/errors/#{error.id}?occurrence=#{middle_id}")
    assert has_element?(view, ".occurrence-nav__when strong", "Occurrence 2 of 3")
    assert has_element?(view, ".occurrence-nav__when .muted", "11 Nov 2026, 11:00:00 UTC")
    assert panel(view, "Logger metadata") == %{"attempt" => "2"}
  end

  test "clicking Newer on an older occurrence shows the next one" do
    start_imison(name: Dashboard, enabled: false)
    error = record_three_attempts()
    [oldest_id, middle_id, _latest_id] = occurrence_ids_oldest_first(error)

    {:ok, view, _html} =
      live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}?occurrence=#{oldest_id}")

    view |> element(".occurrence-nav a", "Newer") |> render_click()

    assert_patch(view, "/errors/errors/#{error.id}?occurrence=#{middle_id}")
    assert has_element?(view, ".occurrence-nav__when strong", "Occurrence 2 of 3")
    assert panel(view, "Logger metadata") == %{"attempt" => "2"}
  end

  test "on the latest occurrence Newer is disabled and on the first one Older is disabled" do
    start_imison(name: Dashboard, enabled: false)
    error = record_three_attempts()
    [oldest_id, _middle_id, _latest_id] = occurrence_ids_oldest_first(error)
    conn = sign_in("/errors", "admin", "secret")

    {:ok, latest_view, _html} = live(conn, "/errors/errors/#{error.id}")
    {:ok, oldest_view, _html} = live(conn, "/errors/errors/#{error.id}?occurrence=#{oldest_id}")

    assert has_element?(latest_view, ".occurrence-nav button[disabled]", "Newer")
    assert has_element?(latest_view, ".occurrence-nav a", "Older")
    assert has_element?(oldest_view, ".occurrence-nav__when strong", "Occurrence 1 of 3")
    assert has_element?(oldest_view, ".occurrence-nav button[disabled]", "Older")
    assert has_element?(oldest_view, ".occurrence-nav a", "Newer")
  end

  test "an occurrence in the URL that belongs to another error or isn't a number shows the latest occurrence" do
    start_imison(name: Dashboard, enabled: false)
    error = record_three_attempts()
    other_error = record(kind: "KeyError")
    [other_occurrence_id] = occurrence_ids_oldest_first(other_error)
    conn = sign_in("/errors", "admin", "secret")

    for occurrence <- [other_occurrence_id, "abc", "99999999999999999999"] do
      {:ok, view, _html} = live(conn, "/errors/errors/#{error.id}?occurrence=#{occurrence}")

      assert has_element?(view, ".occurrence-nav__when strong", "Occurrence 3 of 3")
      assert panel(view, "Logger metadata") == %{"attempt" => "3"}
    end
  end

  test "an error whose occurrences were all pruned shows no occurrence navigation" do
    start_imison(name: Dashboard, enabled: false)
    error = record(kind: "KeyError", occurred_at: days_ago(40))
    Errors.prune(Imison.config(Dashboard), DateTime.utc_now())

    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")

    assert has_element?(view, ".error-head__kind", "KeyError")
    refute has_element?(view, ".occurrence-nav")
  end

  test "resolving an error while an older occurrence is shown keeps that occurrence shown" do
    start_imison(name: Dashboard, enabled: false)
    error = record_three_attempts()
    {:ok, view, _html} = live(sign_in("/errors", "admin", "secret"), "/errors/errors/#{error.id}")
    view |> element(".occurrence-nav a", "Older") |> render_click()

    view |> element(".rail .btn--primary", "Resolve") |> render_click()

    assert has_element?(view, ".error-head__meta .flag--resolved", "Resolved")
    assert has_element?(view, ".occurrence-nav__when strong", "Occurrence 2 of 3")
    assert panel(view, "Logger metadata") == %{"attempt" => "2"}
  end

  defp record_three_attempts do
    [error | _errors] =
      for attempt <- [3, 1, 2] do
        record(
          stacktrace: [{Checkout.Payments, :charge, 1, [file: ~c"lib/checkout/payments.ex", line: 100 + attempt]}],
          context: %{"metadata" => %{"attempt" => attempt}},
          occurred_at: DateTime.new!(~D[2026-11-11], Time.new!(9 + attempt, 0, 0, {0, 6}))
        )
      end

    error
  end

  defp occurrence_ids_oldest_first(%Error{id: error_id}) do
    Occurrence
    |> from(as: :occurrence)
    |> where([occurrence: occurrence], occurrence.error_id == ^error_id)
    |> order_by([occurrence: occurrence], asc: occurrence.occurred_at, asc: occurrence.id)
    |> select([occurrence: occurrence], occurrence.id)
    |> Repo.all()
  end

  defp record(overrides) do
    {:ok, error} = Errors.record(Imison.config(Dashboard), occurrence(overrides))
    error
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

  defp minutes_ago(minutes), do: DateTime.shift(DateTime.utc_now(), minute: -minutes)

  defp days_ago(days), do: DateTime.shift(DateTime.utc_now(), day: -days)

  defp set_status(%Error{id: error_id}, status) do
    Error
    |> from(as: :error)
    |> where([error: error], error.id == ^error_id)
    |> Repo.update_all(set: [status: status])
  end

  defp set_stored_frames(%Error{id: error_id}, stored_frames) do
    Occurrence
    |> from(as: :occurrence)
    |> where([occurrence: occurrence], occurrence.error_id == ^error_id)
    |> Repo.update_all(set: [stacktrace: stored_frames])
  end

  defp error_with_message(message) do
    Error
    |> from(as: :error)
    |> where([error: error], error.message == ^message)
    |> Repo.one!()
  end

  defp document(view), do: view |> render() |> LazyHTML.from_fragment()

  defp status_buttons(view) do
    view
    |> document()
    |> LazyHTML.query(".rail .btn-row .btn")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  defp rail_value(view, label) do
    view
    |> document()
    |> LazyHTML.query(".rail__block:has(.rail__label)")
    |> Enum.find_value(fn block ->
      if block |> LazyHTML.query(".rail__label") |> LazyHTML.text() == label do
        block |> LazyHTML.query(".rail__value") |> LazyHTML.text()
      end
    end)
  end

  defp frames(view) do
    view
    |> document()
    |> LazyHTML.query("details.frame summary")
    |> Enum.map(fn summary ->
      %{
        function: summary |> LazyHTML.query(".frame__fn") |> LazyHTML.text(),
        location: summary |> LazyHTML.query(".frame__loc") |> LazyHTML.text()
      }
    end)
  end

  defp frame_markings(view) do
    view
    |> document()
    |> LazyHTML.query("details.frame")
    |> Enum.map(fn frame ->
      %{
        function: frame |> LazyHTML.query(".frame__fn") |> LazyHTML.text(),
        style: frame_style(frame),
        open: LazyHTML.attribute(frame, "open") != []
      }
    end)
  end

  defp frame_style(frame) do
    frame
    |> LazyHTML.attribute("class")
    |> Enum.flat_map(&String.split/1)
    |> Enum.find(&(&1 in ["frame--app", "frame--dep"]))
  end

  defp panel_titles(view) do
    view
    |> document()
    |> LazyHTML.query(".panel .section-title")
    |> Enum.map(&LazyHTML.text/1)
  end

  defp panel(view, title) do
    section =
      view
      |> document()
      |> LazyHTML.query("section.panel")
      |> Enum.find(&(&1 |> LazyHTML.query(".section-title") |> LazyHTML.text() == title))

    terms = section |> LazyHTML.query(".kv dt") |> Enum.map(&LazyHTML.text/1)
    descriptions = section |> LazyHTML.query(".kv dd") |> Enum.map(&LazyHTML.text/1)

    terms
    |> Enum.zip(descriptions)
    |> Map.new()
  end
end
