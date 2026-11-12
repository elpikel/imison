if Code.ensure_loaded?(Swoosh.Email) do
  defmodule Imison.Notifications.Channels.Email do
    @moduledoc """
    Emails notifications through the host's Swoosh mailer.

    Needs the `mailer` (the host's `Swoosh.Mailer` module) and `from` options;
    the recipients are the channel's stored settings
    (`%{"recipients" => ["ops@example.com"]}`). The email is plain text,
    headed "New error" for a new error and "Came back" (with when it came
    back) for a resolved error that happened again, then the error's kind,
    message, location, occurrence count, when it was first seen and, with the
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
    defp headline(%Message{trigger: :regression}), do: "Came back"

    defp text_body(%Message{} = message) do
      [
        "#{headline(message)}: #{message.kind}",
        opening_line(message),
        "",
        "Message: #{message.message}",
        message.location && "Location: #{message.location}",
        "Occurrences: #{message.occurrence_count}",
        "First seen: #{Format.utc_time(message.first_seen_at)}",
        message.url && "\nView it on the dashboard: #{message.url}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
    end

    defp opening_line(%Message{trigger: :new}), do: nil

    defp opening_line(%Message{trigger: :regression, regressed_at: nil}),
      do: "This error was resolved and happened again."

    defp opening_line(%Message{trigger: :regression, regressed_at: regressed_at}),
      do: "This error was resolved and happened again at #{Format.utc_time(regressed_at)}."
  end
end
