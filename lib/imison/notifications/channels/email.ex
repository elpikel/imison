if Code.ensure_loaded?(Swoosh.Email) do
  defmodule Imison.Notifications.Channels.Email do
    @moduledoc """
    Emails notifications through the host's Swoosh mailer.

    Needs the `mailer` (the host's `Swoosh.Mailer` module) and `from` options;
    the recipients are the channel's stored settings
    (`%{"recipients" => ["ops@example.com"]}`). The email is plain text: the
    error's kind, message, location, when it was first seen and, with the
    `dashboard_url` option, a link to its detail page.

    Compiled only when the host depends on Swoosh.
    """

    @behaviour Imison.Notifications.Channel

    alias Imison.Config
    alias Imison.Notifications.Channel
    alias Imison.Notifications.Message
    alias Imison.Web.Format

    @impl Channel
    def type, do: "email"

    @impl Channel
    def validate_config(%{"recipients" => [_recipient | _more] = recipients}) do
      if Enum.all?(recipients, &is_binary/1) do
        :ok
      else
        {:error, recipients: "must be email addresses"}
      end
    end

    def validate_config(_channel_config), do: {:error, recipients: "must list at least one email address"}

    @impl Channel
    def deliver(_message, _channel_config, %Config{mailer: nil}), do: {:error, :mailer_not_configured}
    def deliver(_message, _channel_config, %Config{from: nil}), do: {:error, :mailer_not_configured}

    def deliver(%Message{} = message, %{"recipients" => recipients}, %Config{mailer: mailer, from: from}) do
      [from: from, to: recipients, subject: subject(message), text_body: text_body(message)]
      |> Swoosh.Email.new()
      |> mailer.deliver([])
      |> case do
        {:ok, _metadata} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end

    defp subject(%Message{location: nil} = message), do: "[Imison] #{headline(message)}: #{message.kind}"
    defp subject(%Message{} = message), do: "[Imison] #{headline(message)}: #{message.kind} in #{message.location}"

    defp headline(%Message{trigger: :new}), do: "New error"

    defp text_body(%Message{} = message) do
      [
        "#{headline(message)}: #{message.kind}",
        "",
        "Message: #{message.message}",
        message.location && "Location: #{message.location}",
        "First seen: #{Format.utc_time(message.first_seen_at)}",
        message.url && "\nView it on the dashboard: #{message.url}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
    end
  end
end
