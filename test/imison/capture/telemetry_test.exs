defmodule Imison.Capture.TelemetryTest do
  use Imison.DataCase, async: false

  import ExUnit.CaptureLog
  import Imison.Test.CaptureHelpers

  test "a Phoenix request exception is recorded with the request's method, path, params and headers in its context" do
    name = start_imison()
    message = unique_message()
    {exception, stacktrace} = raised(message)

    conn =
      :post
      |> Plug.Test.conn("/orders?page=2", %{"order" => %{"id" => "7"}})
      |> Plug.Conn.put_req_header("user-agent", "curl/8.0")

    :telemetry.execute([:phoenix, :router_dispatch, :exception], %{duration: 1_000}, %{
      conn: conn,
      kind: :error,
      reason: exception,
      stacktrace: stacktrace,
      router: __MODULE__,
      route: "/orders"
    })

    wait_for_worker(name)
    assert [%{kind: "RuntimeError", context: %{"request" => request}}] = recorded(message)
    assert request["method"] == "POST"
    assert request["path"] == "/orders"
    assert request["query_string"] == "page=2"
    assert request["params"] == %{"order" => %{"id" => "7"}, "page" => "2"}
    assert request["headers"]["user-agent"] == "curl/8.0"
  end

  test "a Phoenix request exception wrapped by Plug is recorded as the exception it wraps" do
    name = start_imison()
    message = unique_message()
    {exception, stacktrace} = raised(message)
    conn = Plug.Test.conn(:get, "/orders")

    :telemetry.execute([:phoenix, :router_dispatch, :exception], %{duration: 1_000}, %{
      conn: conn,
      kind: :error,
      reason: %Plug.Conn.WrapperError{conn: conn, kind: :error, reason: exception, stack: stacktrace},
      stacktrace: stacktrace
    })

    wait_for_worker(name)
    assert [%{kind: "RuntimeError"}] = recorded(message)
  end

  test "a Phoenix request exception whose params can't be stored as JSON is still recorded" do
    name = start_imison()
    message = unique_message()
    {exception, stacktrace} = raised(message)
    upload = %Plug.Upload{path: "/tmp/plug-1", filename: "invoice.pdf", content_type: "application/pdf"}
    conn = Plug.Test.conn(:post, "/invoices", %{"file" => upload, "range" => {1, 2}})

    :telemetry.execute([:phoenix, :router_dispatch, :exception], %{duration: 1_000}, %{
      conn: conn,
      kind: :error,
      reason: exception,
      stacktrace: stacktrace
    })

    wait_for_worker(name)
    assert [%{context: %{"request" => %{"params" => params}}}] = recorded(message)
    assert params["file"] == inspect(upload)
    assert params["range"] == "{1, 2}"
  end

  test "an Oban job exception is recorded with the job's worker, queue, args and attempt in its context" do
    name = start_imison()
    message = unique_message()
    {exception, stacktrace} = raised(message)

    :telemetry.execute([:oban, :job, :exception], %{duration: 1_000, queue_time: 500}, %{
      job: %{worker: "MyApp.Workers.SendInvoice", queue: "mailers", args: %{"invoice_id" => 7}, attempt: 2},
      kind: :error,
      reason: exception,
      stacktrace: stacktrace,
      state: :failure
    })

    wait_for_worker(name)
    assert [%{kind: "RuntimeError", context: %{"metadata" => %{"job" => job}}}] = recorded(message)

    assert job == %{
             "worker" => "MyApp.Workers.SendInvoice",
             "queue" => "mailers",
             "args" => %{"invoice_id" => 7},
             "attempt" => 2
           }
  end

  test "a raising Phoenix request that the web server also logs is recorded once, from the Phoenix report" do
    name = start_imison()
    message = unique_message()
    {exception, stacktrace} = raised(message)
    conn = Plug.Test.conn(:get, "/orders")

    capture_log(fn ->
      :telemetry.execute([:phoenix, :router_dispatch, :exception], %{duration: 1_000}, %{
        conn: conn,
        kind: :error,
        reason: exception,
        stacktrace: stacktrace
      })

      :logger.error("bandit crash", %{domain: [:bandit], crash_reason: {exception, stacktrace}})
      wait_for_worker(name)
    end)

    assert [%{occurrence_count: 1, context: %{"request" => %{"path" => "/orders"}}}] = recorded(message)
  end
end
