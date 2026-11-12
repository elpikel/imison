defmodule Imison.Notifications.Channels.Slack do
  @moduledoc """
  Posts each notification to a Slack channel through an incoming webhook.

  Its stored setting is the incoming webhook's URL, which must start with
  `https://hooks.slack.com/`: `%{"webhook_url" => "https://hooks.slack.com/services/..."}`.
  The whole URL is the credential, so its field on the Notifications screen
  is a secret: never shown back, and never named in a failure. It isn't in
  the default `channels`; add it there to show its "Slack" panel.

  Each notification is one `{"text": ...}` message in Slack's mrkdwn: a
  bold headline ("New error", "Came back" with when it came back, "Still
  happening" with when it was last seen), then `*kind*: message`, the
  location in backticks, the occurrence count and when it was first seen
  and, with the `dashboard_url` option, an "Open in Imison" link to the
  error. The daily digest is "Daily summary for <date> (UTC)" with the
  sections "New errors", "Came back" and "Most frequent", one line per
  listed error (kind, message, that day's count, location and its link) and
  "and N more" for the errors a section leaves out. The test message sent
  from the Notifications screen says that Slack delivery works.

  The error's kind, message and location are cut to their first line and
  at most 300 characters (ending "…"), so a long exception message can't
  push the counts and the link out of Slack's view, and `&`, `<` and `>`
  in them are escaped as Slack asks, so an error message can't post a
  mention (`<!channel>`) or a link of its own.

  Delivery goes through the same HTTP client as the webhook channel: a 2xx
  answer is a delivery, any other fails it with `{:http_status, status}`,
  and a connection that fails or times out fails it with the reason.
  """

  @behaviour Imison.Notifications.Channel

  alias Imison.Notifications.Channel
  alias Imison.Notifications.HTTP
  alias Imison.Notifications.Message
  alias Imison.Web.Format

  @webhook_url_prefix "https://hooks.slack.com/"
  @excerpt_length 300

  @impl Channel
  def type, do: "slack"

  @impl Channel
  def label, do: "Slack"

  @impl Channel
  def config_fields do
    [
      %{
        name: "webhook_url",
        label: "Incoming webhook URL",
        type: :secret,
        hint: "Create an incoming webhook in your Slack app and paste its https://hooks.slack.com/ URL."
      }
    ]
  end

  @impl Channel
  def validate_config(%{"webhook_url" => webhook_url}) when is_binary(webhook_url) do
    if String.starts_with?(webhook_url, @webhook_url_prefix),
      do: :ok,
      else: {:error, webhook_url: "must be a Slack incoming webhook URL, starting with #{@webhook_url_prefix}"}
  end

  def validate_config(_channel_config), do: {:error, webhook_url: "can't be blank"}

  @impl Channel
  def deliver(%Message{} = message, %{"webhook_url" => webhook_url}, _conf) do
    body = JSON.encode!(%{text: text(message)})
    HTTP.post_json(webhook_url, body, [])
  end

  defp text(%Message{trigger: :test}) do
    "*Test*: Slack delivery from Imison works. Imison posts here when an error matches one of the rules switched on on the Notifications screen."
  end

  defp text(%Message{trigger: :digest, summary: summary}) do
    Enum.join(
      [
        "*Daily summary for #{Calendar.strftime(summary.date, "%-d %b %Y")} (UTC)*",
        digest_section("New errors", summary.new, summary.url),
        digest_section("Came back", summary.came_back, summary.url),
        digest_section("Most frequent", summary.most_frequent, summary.url)
      ],
      "\n\n"
    )
  end

  defp text(%Message{} = message) do
    [
      headline(message),
      "*#{error_text(message.kind)}*: #{error_text(message.message)}",
      message.location && code(message.location),
      "#{occurrences(message.occurrence_count)}, first seen #{Format.utc_time(message.first_seen_at)}",
      link(message.url, "Open in Imison")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp headline(%Message{trigger: :new}), do: "*New error*"
  defp headline(%Message{trigger: :regression, regressed_at: nil}), do: "*Came back*: resolved, then happened again"

  defp headline(%Message{trigger: :regression, regressed_at: regressed_at}),
    do: "*Came back*: resolved, then happened again at #{Format.utc_time(regressed_at)}"

  defp headline(%Message{trigger: :still_happening, last_seen_at: last_seen_at}),
    do: "*Still happening*: last seen at #{Format.utc_time(last_seen_at)}"

  defp digest_section(title, %{lines: []}, _dashboard_url), do: "*#{title}*\nNone."

  defp digest_section(title, %{lines: lines, total: total}, dashboard_url) do
    ["*#{title}*" | Enum.map(lines, &digest_line/1)]
    |> Enum.concat([left_out(total - length(lines), dashboard_url)])
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp digest_line(line) do
    details =
      [occurrences(line.count), line.location && code(line.location)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    ["• *#{error_text(line.kind)}*: #{error_text(line.message)} (#{details})", link(line.url, "Open")]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp left_out(0, _dashboard_url), do: nil
  defp left_out(count, nil), do: "and #{Format.with_thousands_separators(count)} more"

  defp left_out(count, dashboard_url),
    do: "and #{Format.with_thousands_separators(count)} more: #{link(dashboard_url, "Open in Imison")}"

  defp occurrences(1), do: "1 occurrence"
  defp occurrences(count), do: "#{Format.with_thousands_separators(count)} occurrences"

  defp code(text), do: "`" <> (text |> error_text() |> String.replace("`", "'")) <> "`"

  defp link(nil, _label), do: nil
  defp link(url, label), do: "<#{link_target(url)}|#{label}>"

  defp link_target(url) do
    String.replace(url, ["&", "<", ">", "|"], fn
      "&" -> "&amp;"
      "<" -> "%3C"
      ">" -> "%3E"
      "|" -> "%7C"
    end)
  end

  defp error_text(text), do: text |> excerpt() |> escape()

  defp excerpt(text) do
    first_line = text |> String.split(["\r\n", "\n", "\r"], parts: 2) |> hd() |> String.trim_trailing()

    if String.length(first_line) > @excerpt_length,
      do: String.slice(first_line, 0, @excerpt_length - 1) <> "…",
      else: first_line
  end

  defp escape(text) do
    String.replace(text, ["&", "<", ">"], fn
      "&" -> "&amp;"
      "<" -> "&lt;"
      ">" -> "&gt;"
    end)
  end
end
