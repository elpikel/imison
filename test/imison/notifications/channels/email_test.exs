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
