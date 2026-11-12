defmodule Imison.Notifications.Channels.EmailTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias Imison.Config
  alias Imison.Notifications.Channels.Email
  alias Imison.Notifications.Message
  alias Imison.Test.Mailer
  alias Imison.Test.Repo

  test "the subject of an error without a location names only its kind" do
    conf = Config.new(repo: Repo, username: "admin", password: "secret", mailer: Mailer, from: "errors@example.com")

    assert :ok = Email.deliver(message(location: nil), %{"recipients" => ["ops@example.com"]}, conf)

    assert_email_sent(subject: "[Imison] New error: ArgumentError")
  end

  test "a regression without the time it came back is emailed as having happened again" do
    conf = Config.new(repo: Repo, username: "admin", password: "secret", mailer: Mailer, from: "errors@example.com")
    message = message(trigger: :regression, regressed_at: nil)

    assert :ok = Email.deliver(message, %{"recipients" => ["ops@example.com"]}, conf)

    assert_received {:email, %Swoosh.Email{subject: subject, text_body: body}}
    assert subject == "[Imison] Came back: #{message.kind} in #{message.location}"
    assert body =~ "This error was resolved and happened again.\n"
  end

  test "an email isn't sent without a mailer" do
    conf = Config.new(repo: Repo, username: "admin", password: "secret", from: "errors@example.com")

    assert {:error, :mailer_not_configured} = Email.deliver(message([]), %{"recipients" => ["ops@example.com"]}, conf)

    refute_email_sent()
  end

  test "an email isn't sent without a from address" do
    conf = Config.new(repo: Repo, username: "admin", password: "secret", mailer: Mailer)

    assert {:error, :mailer_not_configured} = Email.deliver(message([]), %{"recipients" => ["ops@example.com"]}, conf)

    refute_email_sent()
  end

  test "a daily summary says which sections had no errors that day" do
    conf = Config.new(repo: Repo, username: "admin", password: "secret", mailer: Mailer, from: "errors@example.com")
    most_frequent = %{lines: [summary_line(count: 3)], total: 1}

    message =
      Message.digest(conf, %{date: ~D[2026-11-11], new: no_errors(), came_back: no_errors(), most_frequent: most_frequent})

    assert :ok = Email.deliver(message, %{"recipients" => ["ops@example.com"]}, conf)

    assert_received {:email, %Swoosh.Email{subject: "[Imison] Daily summary for 11 Nov 2026", text_body: body}}
    assert body =~ ~r/New errors\nNone\.\n\nCame back\nNone\.\n\nMost frequent\n/
    assert body =~ "ArgumentError: invalid order id"
    assert body =~ "3 occurrences, MyApp.Orders.fetch/1 (lib/my_app/orders.ex:12)"
    refute body =~ "more"
  end

  test "a daily summary section with more errors than it lists says how many more, with the dashboard link" do
    conf =
      Config.new(
        repo: Repo,
        username: "admin",
        password: "secret",
        mailer: Mailer,
        from: "errors@example.com",
        dashboard_url: "https://app.example.com/errors"
      )

    new = %{lines: Enum.map(1..20, &summary_line(error_id: &1)), total: 23}

    message =
      Message.digest(conf, %{date: ~D[2026-11-11], new: new, came_back: no_errors(), most_frequent: no_errors()})

    assert :ok = Email.deliver(message, %{"recipients" => ["ops@example.com"]}, conf)

    assert_received {:email, %Swoosh.Email{text_body: body}}
    assert body =~ "https://app.example.com/errors/errors/20\nand 3 more: https://app.example.com/errors\n\nCame back"
  end

  defp no_errors, do: %{lines: [], total: 0}

  defp summary_line(overrides) do
    Map.merge(
      %{
        error_id: 7,
        kind: "ArgumentError",
        message: "invalid order id",
        location: "MyApp.Orders.fetch/1 (lib/my_app/orders.ex:12)",
        count: 1
      },
      Map.new(overrides)
    )
  end

  defp message(overrides) do
    struct!(
      %Message{
        trigger: :new,
        error_id: System.unique_integer([:positive]),
        kind: "ArgumentError",
        message: "invalid order id",
        location: "MyApp.Orders.fetch/1 (lib/my_app/orders.ex:12)",
        occurrence_count: 1,
        first_seen_at: ~U[2026-11-12 09:30:00.000000Z],
        last_seen_at: ~U[2026-11-12 09:30:00.000000Z],
        url: nil
      },
      overrides
    )
  end
end
