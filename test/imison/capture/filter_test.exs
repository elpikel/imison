defmodule Imison.Capture.FilterTest do
  use Imison.DataCase, async: false

  import Imison.Test.CaptureHelpers

  test "a password in a failed request's params is stored as filtered while other params are kept" do
    name = start_imison()
    message = unique_message()

    :post
    |> Plug.Test.conn("/users", %{"user" => %{"password" => "s3cret", "name" => "Ann"}})
    |> emit_request_exception(message)

    wait_for_worker(name)
    assert [%{context: %{"request" => %{"params" => params}}}] = recorded(message)
    assert params == %{"user" => %{"password" => "[FILTERED]", "name" => "Ann"}}
  end

  test "the authorization and cookie headers of a failed request are stored as filtered" do
    name = start_imison()
    message = unique_message()

    :get
    |> Plug.Test.conn("/orders")
    |> Plug.Conn.put_req_header("authorization", "Bearer abc123")
    |> Plug.Conn.put_req_header("cookie", "_session=xyz789")
    |> Plug.Conn.put_req_header("user-agent", "curl/8.0")
    |> emit_request_exception(message)

    wait_for_worker(name)
    assert [%{context: %{"request" => %{"headers" => headers}}}] = recorded(message)
    assert headers["authorization"] == "[FILTERED]"
    assert headers["cookie"] == "[FILTERED]"
    assert headers["user-agent"] == "curl/8.0"
  end

  test "a token nested in maps and lists of a failed job's args is stored as filtered at any depth" do
    name = start_imison()
    message = unique_message()
    {exception, stacktrace} = raised(message)

    args = %{
      "account" => %{"api_token" => "tok-1", "id" => 7},
      "webhooks" => [%{"url" => "https://example.test", "credentials" => [%{"token" => "tok-2"}]}]
    }

    :telemetry.execute([:oban, :job, :exception], %{duration: 1_000, queue_time: 500}, %{
      job: %{worker: "MyApp.Workers.SyncAccount", queue: "default", args: args, attempt: 1},
      kind: :error,
      reason: exception,
      stacktrace: stacktrace
    })

    wait_for_worker(name)
    assert [%{context: %{"metadata" => %{"job" => %{"args" => stored_args}}}}] = recorded(message)

    assert stored_args == %{
             "account" => %{"api_token" => "[FILTERED]", "id" => 7},
             "webhooks" => [%{"url" => "https://example.test", "credentials" => [%{"token" => "[FILTERED]"}]}]
           }
  end

  test "params whose names contain a filter word in any case are stored as filtered" do
    name = start_imison()
    message = unique_message()

    :post
    |> Plug.Test.conn("/users", %{"password_confirmation" => "s3cret", "X-Api-Token" => "tok-1", "name" => "Ann"})
    |> emit_request_exception(message)

    wait_for_worker(name)
    assert [%{context: %{"request" => %{"params" => params}}}] = recorded(message)
    assert params == %{"password_confirmation" => "[FILTERED]", "X-Api-Token" => "[FILTERED]", "name" => "Ann"}
  end

  test "a custom filter replaces the default filter words" do
    name = start_imison(filter: ["ssn"])
    message = unique_message()

    :post
    |> Plug.Test.conn("/users", %{"ssn" => "123-45-6789", "password" => "s3cret"})
    |> emit_request_exception(message)

    wait_for_worker(name)
    assert [%{context: %{"request" => %{"params" => params}}}] = recorded(message)
    assert params == %{"ssn" => "[FILTERED]", "password" => "s3cret"}
  end

  test "the query string of a failed request is not stored, its params are filtered instead" do
    name = start_imison()
    message = unique_message()

    :get
    |> Plug.Test.conn("/reset?token=tok-1&page=2", %{})
    |> emit_request_exception(message)

    wait_for_worker(name)
    assert [%{context: %{"request" => request}}] = recorded(message)
    refute Map.has_key?(request, "query_string")
    assert request["params"] == %{"token" => "[FILTERED]", "page" => "2"}
  end

  defp emit_request_exception(conn, message) do
    {exception, stacktrace} = raised(message)

    :telemetry.execute([:phoenix, :router_dispatch, :exception], %{duration: 1_000}, %{
      conn: conn,
      kind: :error,
      reason: exception,
      stacktrace: stacktrace
    })
  end
end
