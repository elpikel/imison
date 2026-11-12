defmodule Imison.Test.WebhookReceiver do
  @moduledoc """
  A local HTTP server standing in for a webhook endpoint, for tests.

  `start/1` serves on a free port of the loopback address under the test's
  supervisor and returns its base URL. Each request it receives is sent to
  the `test` process as `{:webhook_request, %{method:, path:, headers:, body:}}`
  (`headers` as a map of lowercase names) and answered with `status`
  (default 200) and `response_headers` (default none).
  """

  @behaviour Plug

  import Plug.Conn

  @spec start(keyword()) :: String.t()
  def start(opts) do
    server =
      ExUnit.Callbacks.start_supervised!(
        {Bandit, plug: {__MODULE__, opts}, ip: :loopback, port: 0, startup_log: false},
        id: make_ref()
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    "http://127.0.0.1:#{port}"
  end

  @impl Plug
  def init(opts), do: Map.new(opts)

  @impl Plug
  def call(conn, %{test: test} = opts) do
    {:ok, body, conn} = read_body(conn)

    send(
      test,
      {:webhook_request, %{method: conn.method, path: conn.request_path, headers: Map.new(conn.req_headers), body: body}}
    )

    conn
    |> merge_resp_headers(Map.get(opts, :response_headers, []))
    |> send_resp(Map.get(opts, :status, 200), "")
  end
end
