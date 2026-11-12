defmodule Imison.Notifications.Channels.Webhook do
  @moduledoc """
  POSTs each notification as JSON to a URL of your choice.

  Its stored settings are the `url` (http or https) and an optional signing
  `secret`: `%{"url" => "https://hooks.example.com/imison", "secret" => "..."}`.
  It isn't in the default `channels`; add it there to show its panel on the
  Notifications screen.

  The body (`content-type: application/json`) is the
  `Imison.Notifications.Message` as an object: `trigger`, `error_id`, `kind`,
  `message`, `location`, `occurrence_count`, `first_seen_at`,
  `last_seen_at`, `regressed_at`, `url` and `summary` (for the daily digest
  its `date`, `url` and the sections `new`, `came_back` and `most_frequent`,
  each `lines` of `error_id`, `kind`, `message`, `location`, `count` and
  `url` with a `total`; else `null`), times in ISO 8601 and unset fields as `null`.

  With a secret, each request carries `x-imison-timestamp` (Unix seconds)
  and `x-imison-signature: sha256=<hex>`, the lowercase hex HMAC-SHA256 of
  `<timestamp>.<body>` keyed with the secret.

  A 2xx answer is a delivery; any other answer fails it with
  `{:http_status, status}`, and a connection that fails, takes over 5
  seconds to open or over 5 more to answer fails it with the reason, so a
  delivery (and "Send test", which waits for it) takes at most about 10
  seconds. Redirects aren't followed. Failures never name the URL or the
  secret.
  """

  @behaviour Imison.Notifications.Channel

  alias Imison.Notifications.Channel
  alias Imison.Notifications.HTTP
  alias Imison.Notifications.Message

  @impl Channel
  def type, do: "webhook"

  @impl Channel
  def label, do: "Webhook"

  @impl Channel
  def config_fields do
    [
      %{name: "url", label: "URL", type: :url, hint: "Imison POSTs each notification here as JSON."},
      %{
        name: "secret",
        label: "Signing secret",
        type: :secret,
        hint: "Optional. Signs each request in the x-imison-signature header."
      }
    ]
  end

  @impl Channel
  def validate_config(%{"url" => url}) when is_binary(url) do
    if http_url?(url), do: :ok, else: {:error, url: "must be an http:// or https:// URL"}
  end

  def validate_config(_channel_config), do: {:error, url: "can't be blank"}

  @impl Channel
  def deliver(%Message{} = message, %{"url" => url} = channel_config, _conf) do
    body = message |> payload() |> JSON.encode!()
    headers = channel_config |> Map.get("secret") |> signature_headers(body)
    HTTP.post_json(url, body, headers)
  end

  defp payload(%Message{} = message) do
    %{
      trigger: message.trigger,
      error_id: message.error_id,
      kind: message.kind,
      message: message.message,
      location: message.location,
      occurrence_count: message.occurrence_count,
      first_seen_at: message.first_seen_at,
      last_seen_at: message.last_seen_at,
      regressed_at: message.regressed_at,
      url: message.url,
      summary: summary_payload(message.summary)
    }
  end

  defp summary_payload(nil), do: nil

  defp summary_payload(summary) do
    %{
      date: summary.date,
      url: summary.url,
      new: section_payload(summary.new),
      came_back: section_payload(summary.came_back),
      most_frequent: section_payload(summary.most_frequent)
    }
  end

  defp section_payload(%{lines: lines, total: total}), do: %{lines: Enum.map(lines, &line_payload/1), total: total}

  defp line_payload(line), do: Map.take(line, [:error_id, :kind, :message, :location, :count, :url])

  defp http_url?(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host}} when scheme in ["http", "https"] and is_binary(host) and host != "" -> true
      _invalid -> false
    end
  end

  defp signature_headers(secret, body) when is_binary(secret) and secret != "" do
    timestamp = Integer.to_string(System.system_time(:second))
    signature = :hmac |> :crypto.mac(:sha256, secret, [timestamp, ".", body]) |> Base.encode16(case: :lower)
    [{"x-imison-timestamp", timestamp}, {"x-imison-signature", "sha256=" <> signature}]
  end

  defp signature_headers(_secret, _body), do: []
end
