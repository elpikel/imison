defmodule Imison.Web.ErrorLiveTest do
  use Imison.ConnCase, async: false

  import Ecto.Query
  import Imison.Test.CaptureHelpers

  alias Imison.Capture
  alias Imison.Errors
  alias Imison.Errors.Error
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

  defp set_status(%Error{id: error_id}, status) do
    Error
    |> from(as: :error)
    |> where([error: error], error.id == ^error_id)
    |> Repo.update_all(set: [status: status])
  end

  defp error_with_message(message) do
    Error
    |> from(as: :error)
    |> where([error: error], error.message == ^message)
    |> Repo.one!()
  end

  defp document(view), do: view |> render() |> LazyHTML.from_fragment()

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
