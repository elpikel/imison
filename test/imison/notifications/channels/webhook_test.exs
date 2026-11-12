defmodule Imison.Notifications.Channels.WebhookTest do
  use ExUnit.Case, async: true

  alias Imison.Config
  alias Imison.Notifications.Channels.Webhook
  alias Imison.Notifications.Message
  alias Imison.Test.Repo
  alias Imison.Test.WebhookReceiver

  test "a notification is POSTed as JSON to the webhook's URL" do
    url = WebhookReceiver.start(test: self())

    assert :ok = Webhook.deliver(message([]), %{"url" => url <> "/hooks/imison"}, conf())

    assert_received {:webhook_request, %{method: "POST", path: "/hooks/imison", headers: headers}}
    assert headers["content-type"] =~ "application/json"
  end

  test "the JSON body holds the message's fields with times in ISO 8601 and unset fields as null" do
    url = WebhookReceiver.start(test: self())
    message = message(trigger: :regression, regressed_at: ~U[2026-11-12 10:00:00.000000Z])

    assert :ok = Webhook.deliver(message, %{"url" => url}, conf())

    assert_received {:webhook_request, %{body: body}}

    assert JSON.decode!(body) == %{
             "trigger" => "regression",
             "error_id" => message.error_id,
             "kind" => "ArgumentError",
             "message" => "invalid order id",
             "location" => "MyApp.Orders.fetch/1 (lib/my_app/orders.ex:12)",
             "occurrence_count" => 3,
             "first_seen_at" => "2026-11-12T09:30:00.000000Z",
             "last_seen_at" => "2026-11-12T09:45:00.000000Z",
             "regressed_at" => "2026-11-12T10:00:00.000000Z",
             "url" => "https://app.example.com/errors/errors/#{message.error_id}",
             "summary" => nil
           }
  end

  test "a daily digest is POSTed with its summary sections" do
    url = WebhookReceiver.start(test: self())
    line = %{error_id: 7, kind: "ArgumentError", message: "invalid order id", location: nil, count: 4}

    message =
      Message.digest(conf(), %{
        date: ~D[2026-11-11],
        new: %{lines: [line], total: 1},
        came_back: %{lines: [], total: 0},
        most_frequent: %{lines: [line], total: 2}
      })

    assert :ok = Webhook.deliver(message, %{"url" => url}, conf())

    assert_received {:webhook_request, %{body: body}}
    payload = JSON.decode!(body)
    assert %{"trigger" => "digest", "error_id" => nil, "kind" => nil} = payload

    expected_line = %{
      "error_id" => 7,
      "kind" => "ArgumentError",
      "message" => "invalid order id",
      "location" => nil,
      "count" => 4,
      "url" => "https://app.example.com/errors/errors/7"
    }

    assert payload["summary"] == %{
             "date" => "2026-11-11",
             "url" => "https://app.example.com/errors",
             "new" => %{"total" => 1, "lines" => [expected_line]},
             "came_back" => %{"total" => 0, "lines" => []},
             "most_frequent" => %{"total" => 2, "lines" => [expected_line]}
           }
  end

  test "with a signing secret the request carries a timestamp and an HMAC-SHA256 signature of it and the body" do
    url = WebhookReceiver.start(test: self())
    secret = "whsec-#{System.unique_integer([:positive])}"
    before = System.system_time(:second)

    assert :ok = Webhook.deliver(message([]), %{"url" => url, "secret" => secret}, conf())

    assert_received {:webhook_request, %{headers: headers, body: body}}
    timestamp = headers["x-imison-timestamp"]
    assert String.to_integer(timestamp) in before..System.system_time(:second)

    expected_signature =
      :hmac |> :crypto.mac(:sha256, secret, timestamp <> "." <> body) |> Base.encode16(case: :lower)

    assert headers["x-imison-signature"] == "sha256=" <> expected_signature
  end

  test "without a signing secret the request carries no signature" do
    url = WebhookReceiver.start(test: self())

    assert :ok = Webhook.deliver(message([]), %{"url" => url}, conf())

    assert_received {:webhook_request, %{headers: headers}}
    refute Map.has_key?(headers, "x-imison-signature")
    refute Map.has_key?(headers, "x-imison-timestamp")
  end

  test "an endpoint answering with a non-2xx status fails the delivery with that status" do
    url = WebhookReceiver.start(test: self(), status: 503)

    assert {:error, {:http_status, 503}} = Webhook.deliver(message([]), %{"url" => url}, conf())
  end

  test "an endpoint that can't be reached fails the delivery without naming the URL or the secret" do
    url = unreachable_url()
    secret = "whsec-#{System.unique_integer([:positive])}"

    assert {:error, reason} = Webhook.deliver(message([]), %{"url" => url, "secret" => secret}, conf())

    assert reason == {:failed_connect, :econnrefused}
    refute inspect(reason) =~ url
    refute inspect(reason) =~ "127.0.0.1"
    refute inspect(reason) =~ secret
  end

  test "an http or https URL with an optional secret is valid" do
    assert Webhook.validate_config(%{"url" => "https://hooks.example.com/imison"}) == :ok
    assert Webhook.validate_config(%{"url" => "http://10.0.0.5:4000/imison", "secret" => "s3cret"}) == :ok
  end

  test "a URL that isn't http or https is invalid" do
    assert {:error, [url: "must be an http:// or https:// URL"]} =
             Webhook.validate_config(%{"url" => "ftp://files.example.com/imison"})

    assert {:error, [url: "must be an http:// or https:// URL"]} =
             Webhook.validate_config(%{"url" => "hooks.example.com"})
  end

  test "a missing URL is invalid" do
    assert {:error, [url: "can't be blank"]} = Webhook.validate_config(%{})
  end

  defp conf do
    Config.new(repo: Repo, username: "admin", password: "secret", dashboard_url: "https://app.example.com/errors")
  end

  defp unreachable_url do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    "http://127.0.0.1:#{port}/hooks"
  end

  defp message(overrides) do
    error_id = System.unique_integer([:positive])

    struct!(
      %Message{
        trigger: :new,
        error_id: error_id,
        kind: "ArgumentError",
        message: "invalid order id",
        location: "MyApp.Orders.fetch/1 (lib/my_app/orders.ex:12)",
        occurrence_count: 3,
        first_seen_at: ~U[2026-11-12 09:30:00.000000Z],
        last_seen_at: ~U[2026-11-12 09:45:00.000000Z],
        url: "https://app.example.com/errors/errors/#{error_id}"
      },
      overrides
    )
  end
end
