defmodule Imison.Test.PagerChannel do
  @moduledoc """
  A channel a host app writes itself, for tests: titled "Pager", with a
  service URL and a secret API token as its settings.

  It sends nothing anywhere: each delivery sends
  `{:paged, message, channel_config}` to the process registered under this
  module's name, when there is one.
  """

  @behaviour Imison.Notifications.Channel

  alias Imison.Notifications.Channel

  @impl Channel
  def type, do: "pager"

  @impl Channel
  def label, do: "Pager"

  @impl Channel
  def config_fields do
    [
      %{name: "service_url", label: "Service URL", type: :url, hint: "Where the pager service takes alerts."},
      %{name: "token", label: "API token", type: :secret}
    ]
  end

  @impl Channel
  def validate_config(channel_config) do
    channel_config
    |> invalid_settings()
    |> case do
      [] -> :ok
      reasons -> {:error, reasons}
    end
  end

  @impl Channel
  def deliver(message, channel_config, _conf) do
    if test = Process.whereis(__MODULE__), do: send(test, {:paged, message, channel_config})
    :ok
  end

  defp invalid_settings(channel_config) do
    Enum.reject(
      [
        service_url_reason(Map.get(channel_config, "service_url")),
        token_reason(Map.get(channel_config, "token"))
      ],
      &is_nil/1
    )
  end

  defp service_url_reason("https://" <> _rest), do: nil
  defp service_url_reason(_service_url), do: {:service_url, "must start with https://"}

  defp token_reason(token) when is_binary(token) and token != "", do: nil
  defp token_reason(_token), do: {:token, "can't be blank"}
end
