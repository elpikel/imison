defmodule Imison.Notifications.Channels.SlackTest do
  use ExUnit.Case, async: true

  alias Imison.Config
  alias Imison.Notifications.Channels.Slack
  alias Imison.Notifications.Message
  alias Imison.Test.Repo
  alias Imison.Test.WebhookReceiver

  test "a notification is POSTed as JSON to the incoming webhook's URL" do
    url = WebhookReceiver.start(test: self())

    assert :ok = Slack.deliver(message([]), %{"webhook_url" => url <> "/services/T0/B0/x"}, conf())

    assert_received {:webhook_request, %{method: "POST", path: "/services/T0/B0/x", headers: headers, body: body}}
    assert headers["content-type"] =~ "application/json"
    assert %{"text" => _text} = JSON.decode!(body)
  end

  test "a new error is posted with its headline, kind, message, location, counts and link" do
    url = WebhookReceiver.start(test: self())
    message = message([])

    assert :ok = Slack.deliver(message, %{"webhook_url" => url}, conf())

    assert posted_text() ==
             Enum.join(
               [
                 "*New error*",
                 "*ArgumentError*: invalid order id",
                 "`MyApp.Orders.fetch/1 (lib/my_app/orders.ex:12)`",
                 "3 occurrences, first seen 12 Nov 2026, 09:30:00 UTC",
                 "<https://app.example.com/errors/errors/#{message.error_id}|Open in Imison>"
               ],
               "\n"
             )
  end

  test "an error that came back is headed Came back with when it came back" do
    url = WebhookReceiver.start(test: self())
    message = message(trigger: :regression, regressed_at: ~U[2026-11-12 10:00:00.000000Z])

    assert :ok = Slack.deliver(message, %{"webhook_url" => url}, conf())

    assert [
             "*Came back*: resolved, then happened again at 12 Nov 2026, 10:00:00 UTC",
             "*ArgumentError*: invalid order id" | _rest
           ] =
             String.split(posted_text(), "\n")
  end

  test "an error that keeps happening is headed Still happening with when it was last seen" do
    url = WebhookReceiver.start(test: self())

    assert :ok = Slack.deliver(message(trigger: :still_happening), %{"webhook_url" => url}, conf())

    assert ["*Still happening*: last seen at 12 Nov 2026, 09:45:00 UTC", "*ArgumentError*: invalid order id" | _rest] =
             String.split(posted_text(), "\n")
  end

  test "an error without a location or a dashboard link leaves those lines out" do
    url = WebhookReceiver.start(test: self())

    assert :ok = Slack.deliver(message(location: nil, url: nil), %{"webhook_url" => url}, conf())

    assert posted_text() ==
             "*New error*\n*ArgumentError*: invalid order id\n3 occurrences, first seen 12 Nov 2026, 09:30:00 UTC"
  end

  test "the test message says Slack delivery works" do
    url = WebhookReceiver.start(test: self())

    assert :ok = Slack.deliver(Message.test(), %{"webhook_url" => url}, conf())

    assert "*Test*: Slack delivery from Imison works." <> _rest = posted_text()
  end

  test "ampersands and angle brackets in the error are escaped so they can't form links or mentions" do
    url = WebhookReceiver.start(test: self())

    message =
      message(
        kind: "Elixir.Foo<Bar>",
        message: "<!channel> & <https://evil.example.com|Open in Imison>",
        location: "lib/a&b.ex:1 `<x>`"
      )

    assert :ok = Slack.deliver(message, %{"webhook_url" => url}, conf())

    text = posted_text()
    assert text =~ "*Elixir.Foo&lt;Bar&gt;*: &lt;!channel&gt; &amp; &lt;https://evil.example.com|Open in Imison&gt;"
    assert text =~ "`lib/a&amp;b.ex:1 '&lt;x&gt;'`"
    refute text =~ "<!channel>"
    refute text =~ "<https://evil.example.com"
  end

  test "a dashboard link with a pipe or angle bracket can't break out of the link" do
    url = WebhookReceiver.start(test: self())
    message = message(url: "https://app.example.com/errors?a=1&b=<2>|x")

    assert :ok = Slack.deliver(message, %{"webhook_url" => url}, conf())

    assert posted_text() =~ "<https://app.example.com/errors?a=1&amp;b=%3C2%3E%7Cx|Open in Imison>"
  end

  test "a long multi-line error is cut to its first line and 300 characters so the counts and link still show" do
    url = WebhookReceiver.start(test: self())
    first_line = String.duplicate("x", 400)
    message = message(message: first_line <> "\n" <> String.duplicate("stack frame\n", 500))

    assert :ok = Slack.deliver(message, %{"webhook_url" => url}, conf())

    assert [_headline, error_line, _location, counts, link] = String.split(posted_text(), "\n")
    assert error_line == "*ArgumentError*: " <> String.duplicate("x", 299) <> "…"
    assert counts == "3 occurrences, first seen 12 Nov 2026, 09:30:00 UTC"
    assert link == "<https://app.example.com/errors/errors/#{message.error_id}|Open in Imison>"
  end

  test "a long multi-line error in the digest stays on one capped line with its count and link" do
    url = WebhookReceiver.start(test: self())

    line = %{
      error_id: 7,
      kind: "ArgumentError",
      message: String.duplicate("y", 400) <> "\nsecond line",
      location: "lib/orders.ex:12\nlib/other.ex:3",
      count: 4
    }

    message =
      Message.digest(conf(), %{
        date: ~D[2026-11-11],
        new: %{lines: [line], total: 2},
        came_back: %{lines: [], total: 0},
        most_frequent: %{lines: [], total: 0}
      })

    assert :ok = Slack.deliver(message, %{"webhook_url" => url}, conf())

    assert posted_text() =~
             "*New errors*\n• *ArgumentError*: " <>
               String.duplicate("y", 299) <>
               "… (4 occurrences, `lib/orders.ex:12`) <https://app.example.com/errors/errors/7|Open>\n" <>
               "and 1 more: <https://app.example.com/errors|Open in Imison>\n"
  end

  test "a daily digest posts its three sections with capped lines and how many it left out" do
    url = WebhookReceiver.start(test: self())
    line = %{error_id: 7, kind: "ArgumentError", message: "invalid <order> id", location: "lib/orders.ex:12", count: 4}
    other_line = %{error_id: 8, kind: "KeyError", message: "key :id not found", location: nil, count: 1}

    message =
      Message.digest(conf(), %{
        date: ~D[2026-11-11],
        new: %{lines: [line, other_line], total: 5},
        came_back: %{lines: [], total: 0},
        most_frequent: %{lines: [line], total: 1}
      })

    assert :ok = Slack.deliver(message, %{"webhook_url" => url}, conf())

    assert posted_text() ==
             Enum.join(
               [
                 "*Daily summary for 11 Nov 2026 (UTC)*",
                 "",
                 "*New errors*",
                 "• *ArgumentError*: invalid &lt;order&gt; id (4 occurrences, `lib/orders.ex:12`) <https://app.example.com/errors/errors/7|Open>",
                 "• *KeyError*: key :id not found (1 occurrence) <https://app.example.com/errors/errors/8|Open>",
                 "and 3 more: <https://app.example.com/errors|Open in Imison>",
                 "",
                 "*Came back*",
                 "None.",
                 "",
                 "*Most frequent*",
                 "• *ArgumentError*: invalid &lt;order&gt; id (4 occurrences, `lib/orders.ex:12`) <https://app.example.com/errors/errors/7|Open>"
               ],
               "\n"
             )
  end

  test "a digest without a dashboard link says how many it left out without links" do
    url = WebhookReceiver.start(test: self())
    line = %{error_id: 7, kind: "ArgumentError", message: "invalid order id", location: nil, count: 1_200}
    conf_without_link = Config.new(repo: Repo, username: "admin", password: "secret")

    message =
      Message.digest(conf_without_link, %{
        date: ~D[2026-11-11],
        new: %{lines: [line], total: 1_201},
        came_back: %{lines: [], total: 0},
        most_frequent: %{lines: [], total: 0}
      })

    assert :ok = Slack.deliver(message, %{"webhook_url" => url}, conf_without_link)

    text = posted_text()
    assert text =~ "• *ArgumentError*: invalid order id (1,200 occurrences)\nand 1,200 more\n"
    refute text =~ "<http"
  end

  test "Slack answering with a non-2xx status fails the delivery with that status" do
    url = WebhookReceiver.start(test: self(), status: 404)

    assert {:error, {:http_status, 404}} = Slack.deliver(message([]), %{"webhook_url" => url}, conf())
  end

  test "an incoming webhook URL on hooks.slack.com is valid" do
    assert Slack.validate_config(%{"webhook_url" => "https://hooks.slack.com/services/T000/B000/XXXX"}) == :ok
  end

  test "a URL that isn't an https://hooks.slack.com/ URL is invalid and the error doesn't show it" do
    for webhook_url <- [
          "http://hooks.slack.com/services/T000/B000/XXXX",
          "https://hooks.slack.com.evil.example.com/services/T000",
          "https://example.com/services/T000/B000/XXXX"
        ] do
      assert {:error, [webhook_url: reason]} = Slack.validate_config(%{"webhook_url" => webhook_url})
      assert reason == "must be a Slack incoming webhook URL, starting with https://hooks.slack.com/"
    end
  end

  test "a missing webhook URL is invalid" do
    assert {:error, [webhook_url: "can't be blank"]} = Slack.validate_config(%{})
  end

  defp posted_text do
    assert_received {:webhook_request, %{body: body}}
    %{"text" => text} = JSON.decode!(body)
    text
  end

  defp conf do
    Config.new(repo: Repo, username: "admin", password: "secret", dashboard_url: "https://app.example.com/errors")
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
