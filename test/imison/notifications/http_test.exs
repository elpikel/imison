defmodule Imison.Notifications.HTTPTest do
  use ExUnit.Case, async: true

  alias Imison.Notifications.HTTP
  alias Imison.Test.WebhookReceiver

  test "a 2xx answer is ok" do
    url = WebhookReceiver.start(test: self(), status: 204)

    assert HTTP.post_json(url, ~s({"ok":true}), []) == :ok

    assert_received {:webhook_request, %{method: "POST", body: ~s({"ok":true})}}
  end

  test "a redirect isn't followed and fails with its status" do
    url = WebhookReceiver.start(test: self(), status: 302, response_headers: [{"location", "/elsewhere"}])

    assert HTTP.post_json(url <> "/hooks", "{}", []) == {:error, {:http_status, 302}}

    assert_received {:webhook_request, %{path: "/hooks"}}
    refute_received {:webhook_request, %{path: "/elsewhere"}}
  end

  test "a request that fails before reaching the server returns a reason without the URL" do
    url = "http://127.0.0.1/" <> <<0xFF>> <> "?token=webhook-token-1"

    assert HTTP.post_json(url, "{}", []) == {:error, :request_failed}
  end

  test "an https server whose certificate no trusted authority signed is refused before anything is sent" do
    url = start_untrusted_https_server()

    assert {:error, reason} = HTTP.post_json(url, "{}", [])

    assert reason == {:failed_connect, :unknown_ca}
    refute_received {:webhook_request, _request}
  end

  defp start_untrusted_https_server do
    certificate_options = [key: {:namedCurve, :secp256r1}, digest: :sha256]

    %{server_config: server_config} =
      :public_key.pkix_test_data(%{
        server_chain: %{root: certificate_options, intermediates: [], peer: certificate_options},
        client_chain: %{root: certificate_options, intermediates: [], peer: certificate_options}
      })

    server =
      start_supervised!(
        {Bandit,
         plug: {WebhookReceiver, test: self()},
         scheme: :https,
         ip: :loopback,
         port: 0,
         startup_log: false,
         thousand_island_options: [transport_options: Keyword.take(server_config, [:cert, :key])]}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    "https://localhost:#{port}/hooks"
  end
end
