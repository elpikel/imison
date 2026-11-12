defmodule Imison.NotificationsTest do
  use Imison.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  import Imison.Test.CaptureHelpers
  import Swoosh.TestAssertions

  alias Ecto.Adapters.SQL.Sandbox
  alias Imison.Capture
  alias Imison.Config
  alias Imison.Errors
  alias Imison.Errors.Error
  alias Imison.Notifications
  alias Imison.Notifications.Channels.Email
  alias Imison.Notifications.ChannelSetting
  alias Imison.Notifications.Delivery
  alias Imison.Notifications.Rule
  alias Imison.Test.Mailer
  alias Imison.Web.Format

  defmodule FailingMailer do
    @moduledoc false

    def deliver(_email, _config), do: {:error, :smtp_unavailable}
  end

  defmodule RaisingMailer do
    @moduledoc false

    def deliver(_email, _config), do: raise("SMTP connection refused")
  end

  defmodule BlockingMailer do
    @moduledoc false

    def deliver(_email, _config) do
      send(Imison.NotificationsTest, {:delivering, self()})

      receive do
        :release -> {:ok, %{}}
      end
    end
  end

  test "a new error sends one email through the host's mailer from the from address to the channel's recipients" do
    set_swoosh_global()
    name = start_mailing_imison()
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com", "dev@example.com"]}})

    capture_new_error(name)

    wait_for_worker(name)
    assert_email_sent(from: {"", "errors@example.com"}, to: [{"", "ops@example.com"}, {"", "dev@example.com"}])
    refute_email_sent()
  end

  test "the email's subject names the error's kind and location" do
    set_swoosh_global()
    name = start_mailing_imison()
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    message = capture_new_error(name)

    wait_for_worker(name)
    error = recorded_error(message)
    assert_email_sent(subject: "[Imison] New error: #{error.kind} in #{error.location}")
  end

  test "the email's body has the error's kind, message, location, first seen and a link to its detail page" do
    set_swoosh_global()
    name = start_mailing_imison(dashboard_url: "https://app.example.com/errors/")
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    message = capture_new_error(name)

    wait_for_worker(name)
    error = recorded_error(message)
    assert_received {:email, %Swoosh.Email{text_body: body}}
    assert body =~ error.kind
    assert body =~ message
    assert body =~ error.location
    assert body =~ Format.utc_time(error.first_seen_at)
    assert body =~ "https://app.example.com/errors/errors/#{error.id}"
  end

  test "without dashboard_url the email is sent without a link" do
    set_swoosh_global()
    name = start_mailing_imison()
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    capture_new_error(name)

    wait_for_worker(name)
    assert_received {:email, %Swoosh.Email{text_body: body}}
    refute body =~ "http"
  end

  test "another occurrence of an existing error sends and records nothing without a stored still happening rule" do
    set_swoosh_global()
    name = start_mailing_imison()
    error = capture_existing_error(name, ~U[2026-11-12 09:30:00.000000Z])
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    Capture.capture(name, %{error.event | occurred_at: ~U[2026-11-12 10:15:00.000000Z]})

    wait_for_worker(name)
    refute_email_sent()
    assert deliveries(error.id) == []
  end

  test "an unresolved error that happens 50 times within one hour sends one still happening reminder" do
    set_swoosh_global()
    name = start_mailing_imison()
    error = capture_existing_error(name, ~U[2026-11-12 09:30:00.000000Z])
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})
    {:ok, _rule} = Notifications.put_rule(Imison.config(name), :still_happening, true)

    for minute <- 1..50 do
      Capture.capture(name, %{error.event | occurred_at: DateTime.shift(~U[2026-11-12 10:00:00.000000Z], minute: minute)})
    end

    wait_for_worker(name)
    assert_email_sent(to: [{"", "ops@example.com"}])
    refute_email_sent()
    assert [%Delivery{trigger: :still_happening}] = deliveries(error.id)
  end

  test "an unresolved error that happens 50 times within one hour tries to claim its reminder once" do
    set_swoosh_global()
    name = start_mailing_imison()
    error = capture_existing_error(name, ~U[2026-11-12 09:30:00.000000Z])
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})
    {:ok, _rule} = Notifications.put_rule(Imison.config(name), :still_happening, true)
    handler_id = "imison-notifications-test-#{System.unique_integer([:positive])}"
    :ok = :telemetry.attach(handler_id, [:imison, :test, :repo, :query], &__MODULE__.report_delivery_insert/4, self())
    on_exit(fn -> :telemetry.detach(handler_id) end)

    for minute <- 1..50 do
      Capture.capture(name, %{error.event | occurred_at: DateTime.shift(~U[2026-11-12 10:00:00.000000Z], minute: minute)})
    end

    wait_for_worker(name)
    assert_received :delivery_insert
    refute_received :delivery_insert
  end

  test "an error still happening in the next hour sends another reminder" do
    set_swoosh_global()
    name = start_mailing_imison()
    error = capture_existing_error(name, ~U[2026-11-12 09:30:00.000000Z])
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})
    {:ok, _rule} = Notifications.put_rule(Imison.config(name), :still_happening, true)
    Capture.capture(name, %{error.event | occurred_at: ~U[2026-11-12 10:15:00.000000Z]})
    wait_for_worker(name)
    assert_email_sent()

    Capture.capture(name, %{error.event | occurred_at: ~U[2026-11-12 11:05:00.000000Z]})

    wait_for_worker(name)
    assert_email_sent()

    assert error.id |> deliveries() |> Enum.map(& &1.period) |> Enum.sort(DateTime) == [
             ~U[2026-11-12 10:00:00Z],
             ~U[2026-11-12 11:00:00Z]
           ]
  end

  test "a sent reminder is recorded with its channel, error, the still happening trigger, the hour as its period and sent" do
    set_swoosh_global()
    name = start_mailing_imison()
    error = capture_existing_error(name, ~U[2026-11-12 09:30:00.000000Z])
    channel = put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})
    {:ok, _rule} = Notifications.put_rule(Imison.config(name), :still_happening, true)

    Capture.capture(name, %{error.event | occurred_at: ~U[2026-11-12 10:15:00.000000Z]})

    wait_for_worker(name)
    channel_id = channel.id
    error_id = error.id

    assert [
             %Delivery{
               channel_id: ^channel_id,
               error_id: ^error_id,
               trigger: :still_happening,
               period: ~U[2026-11-12 10:00:00Z],
               status: :sent,
               sent_at: %DateTime{}
             }
           ] = deliveries(error.id)
  end

  test "a reminder the mailer fails to send is recorded as failed for its hour" do
    name = start_mailing_imison(mailer: FailingMailer)
    error = capture_existing_error(name, ~U[2026-11-12 09:30:00.000000Z])
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})
    {:ok, _rule} = Notifications.put_rule(Imison.config(name), :still_happening, true)

    with_log(fn ->
      Capture.capture(name, %{error.event | occurred_at: ~U[2026-11-12 10:15:00.000000Z]})
      wait_for_worker(name)
    end)

    assert [%Delivery{trigger: :still_happening, period: ~U[2026-11-12 10:00:00Z], status: :failed, sent_at: %DateTime{}}] =
             deliveries(error.id)
  end

  test "an ignored error that happens again sends no reminder" do
    set_swoosh_global()
    name = start_mailing_imison()
    error = capture_and_set_status(name, :ignored)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})
    {:ok, _rule} = Notifications.put_rule(Imison.config(name), :still_happening, true)

    Capture.capture(name, %{error.event | occurred_at: DateTime.utc_now()})

    wait_for_worker(name)
    refute_email_sent()
    assert deliveries(error.id) == []
  end

  test "the occurrence that creates an error sends only the new error notification" do
    set_swoosh_global()
    name = start_mailing_imison()
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})
    {:ok, _rule} = Notifications.put_rule(Imison.config(name), :still_happening, true)

    message = capture_new_error(name)

    wait_for_worker(name)
    assert_email_sent()
    refute_email_sent()
    assert [%Delivery{trigger: :new}] = deliveries(recorded_error(message).id)
  end

  test "the occurrence that reopens a resolved error sends only the regression notification" do
    set_swoosh_global()
    name = start_mailing_imison()
    error = capture_and_set_status(name, :resolved)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})
    {:ok, _rule} = Notifications.put_rule(Imison.config(name), :still_happening, true)

    Capture.capture(name, %{error.event | occurred_at: DateTime.utc_now()})

    wait_for_worker(name)
    assert_email_sent()
    refute_email_sent()
    assert [%Delivery{trigger: :regression}] = deliveries(error.id)
  end

  test "the reminder email is headed Still happening with the occurrence count and a link to the error" do
    set_swoosh_global()
    name = start_mailing_imison(dashboard_url: "https://app.example.com/errors")
    error = capture_existing_error(name, ~U[2026-11-12 09:30:00.000000Z])
    Capture.capture(name, %{error.event | occurred_at: ~U[2026-11-12 09:45:00.000000Z]})
    wait_for_worker(name)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})
    {:ok, _rule} = Notifications.put_rule(Imison.config(name), :still_happening, true)

    Capture.capture(name, %{error.event | occurred_at: ~U[2026-11-12 10:15:00.000000Z]})

    wait_for_worker(name)
    still_happening = Repo.get!(Error, error.id)
    assert_received {:email, %Swoosh.Email{subject: subject, text_body: body}}
    assert subject == "[Imison] Still happening: #{still_happening.kind} in #{still_happening.location}"
    assert body =~ "Occurrences: 3"
    assert body =~ "https://app.example.com/errors/errors/#{error.id}"
  end

  test "a new error sends no email when the new rule is stored as disabled" do
    set_swoosh_global()
    name = start_mailing_imison()
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})
    {:ok, _rule} = Notifications.put_rule(Imison.config(name), :new, false)

    capture_new_error(name)

    wait_for_worker(name)
    refute_email_sent()
  end

  test "a new error sends no email when no email channel is stored" do
    set_swoosh_global()
    name = start_mailing_imison()

    capture_new_error(name)

    wait_for_worker(name)
    refute_email_sent()
  end

  test "a new error sends no email when the email channel is disabled" do
    set_swoosh_global()
    name = start_mailing_imison()
    put_email_channel(name, %{enabled: false, config: %{"recipients" => ["ops@example.com"]}})

    capture_new_error(name)

    wait_for_worker(name)
    refute_email_sent()
  end

  test "a new error sends no email when the email channel has no recipients" do
    set_swoosh_global()
    name = start_mailing_imison()
    put_email_channel(name, %{enabled: true, config: %{"recipients" => []}})

    capture_new_error(name)

    wait_for_worker(name)
    refute_email_sent()
  end

  test "a sent email is recorded as a sent delivery of the new trigger for its channel and error" do
    set_swoosh_global()
    name = start_mailing_imison()
    channel = put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    message = capture_new_error(name)

    wait_for_worker(name)
    channel_id = channel.id

    assert [%Delivery{channel_id: ^channel_id, trigger: :new, status: :sent, sent_at: %DateTime{}}] =
             deliveries(recorded_error(message).id)
  end

  test "an email the mailer fails to send is recorded as a failed delivery" do
    name = start_mailing_imison(mailer: FailingMailer)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    {message, _log} =
      with_log(fn ->
        message = capture_new_error(name)
        wait_for_worker(name)
        message
      end)

    assert [%Delivery{trigger: :new, status: :failed, sent_at: %DateTime{}}] = deliveries(recorded_error(message).id)
  end

  test "a mailer that returns an error is logged under the imison domain" do
    name = start_mailing_imison(mailer: FailingMailer)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    log =
      capture_log([metadata: [:domain]], fn ->
        capture_new_error(name)
        wait_for_worker(name)
      end)

    assert log =~ ~r/domain=elixir\.imison \[error\] Imison failed to deliver a notification.*smtp_unavailable/s
  end

  test "a mailer that raises is logged under the imison domain" do
    name = start_mailing_imison(mailer: RaisingMailer)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    log =
      capture_log([metadata: [:domain]], fn ->
        capture_new_error(name)
        wait_for_worker(name)
      end)

    assert log =~ ~r/domain=elixir\.imison \[error\] Imison failed to deliver a notification.*SMTP connection refused/s
  end

  test "a mailer that raises records a failed delivery" do
    name = start_mailing_imison(mailer: RaisingMailer)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    {message, _log} =
      with_log(fn ->
        message = capture_new_error(name)
        wait_for_worker(name)
        message
      end)

    assert [%Delivery{status: :failed}] = deliveries(recorded_error(message).id)
  end

  test "an error whose email fails is still recorded" do
    name = start_mailing_imison(mailer: RaisingMailer)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    {message, _log} =
      with_log(fn ->
        message = capture_new_error(name)
        wait_for_worker(name)
        message
      end)

    assert [%{occurrence_count: 1}] = recorded(message)
  end

  test "the capture worker keeps recording while a mailer is still sending" do
    Process.register(self(), __MODULE__)
    name = start_mailing_imison(mailer: BlockingMailer)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})
    capture_new_error(name)
    assert_receive {:delivering, _task}

    message = capture_new_error(name)

    wait_for_recording(name)
    assert [%{occurrence_count: 1}] = recorded(message)
    assert_receive {:delivering, _task}
  end

  test "a resolved error that comes back sends one regression notification" do
    set_swoosh_global()
    name = start_mailing_imison()
    error = capture_and_set_status(name, :resolved)
    channel = put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    Capture.capture(name, %{error.event | occurred_at: DateTime.utc_now()})

    wait_for_worker(name)
    channel_id = channel.id
    assert_email_sent(to: [{"", "ops@example.com"}])
    refute_email_sent()
    assert [%Delivery{channel_id: ^channel_id, trigger: :regression, status: :sent}] = deliveries(error.id)
  end

  test "a resolved error that comes back sends nothing when the regression rule is stored as disabled" do
    set_swoosh_global()
    name = start_mailing_imison()
    error = capture_and_set_status(name, :resolved)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})
    {:ok, _rule} = Notifications.put_rule(Imison.config(name), :regression, false)

    Capture.capture(name, %{error.event | occurred_at: DateTime.utc_now()})

    wait_for_worker(name)
    refute_email_sent()
    assert deliveries(error.id) == []
  end

  test "an ignored error that happens again sends nothing" do
    set_swoosh_global()
    name = start_mailing_imison()
    error = capture_and_set_status(name, :ignored)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    Capture.capture(name, %{error.event | occurred_at: DateTime.utc_now()})

    wait_for_worker(name)
    refute_email_sent()
    assert deliveries(error.id) == []
  end

  test "a resolved error marked unresolved again by hand sends nothing when it happens again" do
    set_swoosh_global()
    name = start_mailing_imison()
    error = capture_and_set_status(name, :resolved)
    {:ok, 1} = Errors.set_status(Imison.config(name), [error.id], :unresolved)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    Capture.capture(name, %{error.event | occurred_at: DateTime.utc_now()})

    wait_for_worker(name)
    refute_email_sent()
    assert deliveries(error.id) == []
  end

  test "the email of a resolved error that comes back is headed Came back with when it came back" do
    set_swoosh_global()
    name = start_mailing_imison()
    error = capture_and_set_status(name, :resolved)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    Capture.capture(name, %{error.event | occurred_at: DateTime.utc_now()})

    wait_for_worker(name)
    came_back = Repo.get!(Error, error.id)
    assert_received {:email, %Swoosh.Email{subject: subject, text_body: body}}
    assert subject == "[Imison] Came back: #{came_back.kind} in #{came_back.location}"
    assert body =~ "This error was resolved and happened again at #{Format.utc_time(came_back.regressed_at)}."
  end

  test "the email of a resolved error that comes back has its occurrence count, first seen and a link to its detail page" do
    set_swoosh_global()
    name = start_mailing_imison(dashboard_url: "https://app.example.com/errors")
    error = capture_and_set_status(name, :resolved)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    Capture.capture(name, %{error.event | occurred_at: DateTime.utc_now()})

    wait_for_worker(name)
    came_back = Repo.get!(Error, error.id)
    assert_received {:email, %Swoosh.Email{text_body: body}}
    assert body =~ "Occurrences: 2"
    assert body =~ "First seen: #{Format.utc_time(came_back.first_seen_at)}"
    assert body =~ "https://app.example.com/errors/errors/#{error.id}"
  end

  test "the email of a new error is headed New error and doesn't say it came back" do
    set_swoosh_global()
    name = start_mailing_imison()
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    message = capture_new_error(name)

    wait_for_worker(name)
    error = recorded_error(message)
    assert_received {:email, %Swoosh.Email{subject: subject, text_body: body}}
    assert subject == "[Imison] New error: #{error.kind} in #{error.location}"
    assert body =~ "New error: #{error.kind}"
    refute body =~ "happened again"
  end

  test "a muted resolved error that comes back sends nothing and records no delivery with every rule on" do
    set_swoosh_global()
    name = start_mailing_imison()
    error = capture_and_set_status(name, :resolved)
    {:ok, 1} = Errors.set_muted(Imison.config(name), [error.id], true)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})
    turn_every_rule_on(name)

    Capture.capture(name, %{error.event | occurred_at: DateTime.utc_now()})

    wait_for_worker(name)
    refute_email_sent()
    assert deliveries(error.id) == []
  end

  test "a muted unresolved error that keeps happening sends no reminder and records no delivery with every rule on" do
    set_swoosh_global()
    name = start_mailing_imison()
    error = capture_existing_error(name, ~U[2026-11-12 09:30:00.000000Z])
    {:ok, 1} = Errors.set_muted(Imison.config(name), [error.id], true)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})
    turn_every_rule_on(name)

    Capture.capture(name, %{error.event | occurred_at: ~U[2026-11-12 10:15:00.000000Z]})

    wait_for_worker(name)
    refute_email_sent()
    assert deliveries(error.id) == []
  end

  test "a resolved error muted then unmuted sends the regression notification when it comes back" do
    set_swoosh_global()
    name = start_mailing_imison()
    error = capture_and_set_status(name, :resolved)
    {:ok, 1} = Errors.set_muted(Imison.config(name), [error.id], true)
    {:ok, 1} = Errors.set_muted(Imison.config(name), [error.id], false)
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    Capture.capture(name, %{error.event | occurred_at: DateTime.utc_now()})

    wait_for_worker(name)
    assert_email_sent(to: [{"", "ops@example.com"}])
    assert [%Delivery{trigger: :regression, status: :sent}] = deliveries(error.id)
  end

  test "with the digest rule on, a day's digest is emailed once as the daily summary for that day" do
    conf = digest_config()
    put_digest_email_channel(conf)
    {:ok, _rule} = Notifications.put_rule(conf, :digest, true)
    record_on(conf, ~U[2026-11-11 10:00:00.000000Z])

    assert Notifications.send_digest(conf, ~D[2026-11-11]) == :ok

    assert_email_sent(to: [{"", "ops@example.com"}], subject: "[Imison] Daily summary for 11 Nov 2026")
    refute_email_sent()
  end

  test "a sent digest is recorded with its channel, no error, the digest trigger, the day as its period and sent" do
    conf = digest_config()
    channel = put_digest_email_channel(conf)
    {:ok, _rule} = Notifications.put_rule(conf, :digest, true)
    record_on(conf, ~U[2026-11-11 10:00:00.000000Z])

    Notifications.send_digest(conf, ~D[2026-11-11])

    channel_id = channel.id

    assert [
             %Delivery{
               channel_id: ^channel_id,
               error_id: nil,
               trigger: :digest,
               period: ~U[2026-11-11 00:00:00Z],
               status: :sent,
               sent_at: %DateTime{}
             }
           ] = Repo.all(Delivery)
  end

  test "the digest email lists the day's new errors, the errors that came back and the most frequent with counts and links" do
    conf = digest_config(dashboard_url: "https://app.example.com/errors")
    put_digest_email_channel(conf)
    {:ok, _rule} = Notifications.put_rule(conf, :digest, true)
    new_error = record_on(conf, ~U[2026-11-11 10:00:00.000000Z])
    came_back = record_on(conf, ~U[2026-11-01 10:00:00.000000Z])
    record_again(conf, came_back, ~U[2026-11-11 11:00:00.000000Z])
    record_again(conf, came_back, ~U[2026-11-11 12:00:00.000000Z])
    set_regressed_at(came_back, ~U[2026-11-11 11:00:00.000000Z])

    Notifications.send_digest(conf, ~D[2026-11-11])

    assert_received {:email, %Swoosh.Email{text_body: body}}
    [_head, new_section] = String.split(body, "New errors", parts: 2)
    [new_section, came_back_section] = String.split(new_section, "Came back", parts: 2)
    [came_back_section, most_frequent_section] = String.split(came_back_section, "Most frequent", parts: 2)
    assert new_section =~ new_error.message
    assert new_section =~ "https://app.example.com/errors/errors/#{new_error.id}"
    refute new_section =~ came_back.message
    assert came_back_section =~ came_back.message
    assert came_back_section =~ "https://app.example.com/errors/errors/#{came_back.id}"
    assert most_frequent_section =~ ~r/#{came_back.message}.*2 occurrences.*#{new_error.message}.*1 occurrence/s
  end

  test "a muted error is still listed in the digest" do
    conf = digest_config()
    put_digest_email_channel(conf)
    {:ok, _rule} = Notifications.put_rule(conf, :digest, true)
    error = record_on(conf, ~U[2026-11-11 10:00:00.000000Z])
    {:ok, 1} = Errors.set_muted(conf, [error.id], true)

    Notifications.send_digest(conf, ~D[2026-11-11])

    assert_received {:email, %Swoosh.Email{text_body: body}}
    assert body =~ error.message
  end

  test "a day when nothing happened sends no digest and claims nothing" do
    conf = digest_config()
    put_digest_email_channel(conf)
    {:ok, _rule} = Notifications.put_rule(conf, :digest, true)
    record_on(conf, ~U[2026-11-10 10:00:00.000000Z])

    assert Notifications.send_digest(conf, ~D[2026-11-11]) == :ok

    refute_email_sent()
    assert Repo.all(Delivery) == []
  end

  test "without a stored digest rule no digest is sent and nothing is claimed" do
    conf = digest_config()
    put_digest_email_channel(conf)
    record_on(conf, ~U[2026-11-11 10:00:00.000000Z])

    assert Notifications.send_digest(conf, ~D[2026-11-11]) == :rule_off

    refute_email_sent()
    assert Repo.all(Delivery) == []
  end

  test "a day's digest sent a second time sends nothing more" do
    conf = digest_config()
    put_digest_email_channel(conf)
    {:ok, _rule} = Notifications.put_rule(conf, :digest, true)
    record_on(conf, ~U[2026-11-11 10:00:00.000000Z])
    Notifications.send_digest(conf, ~D[2026-11-11])
    assert_email_sent()

    assert Notifications.send_digest(conf, ~D[2026-11-11]) == :ok

    refute_email_sent()
    assert [%Delivery{trigger: :digest}] = Repo.all(Delivery)
  end

  test "a digest the mailer fails to send is logged under the imison domain and recorded as failed for its day" do
    conf = digest_config(mailer: FailingMailer)
    put_digest_email_channel(conf)
    {:ok, _rule} = Notifications.put_rule(conf, :digest, true)
    record_on(conf, ~U[2026-11-11 10:00:00.000000Z])

    log = capture_log([metadata: [:domain]], fn -> assert Notifications.send_digest(conf, ~D[2026-11-11]) == :ok end)

    assert log =~ ~r/domain=elixir\.imison \[error\] Imison failed to deliver a notification.*smtp_unavailable/s
    assert [%Delivery{trigger: :digest, period: ~U[2026-11-11 00:00:00Z], status: :failed}] = Repo.all(Delivery)
  end

  test "processes on their own connections sending the same day's digest at once send one email and record one delivery" do
    set_swoosh_global()
    conf = digest_config()
    senders = 20
    kind = "Imison.DigestConcurrencyError#{System.unique_integer([:positive])}"
    clean_up_committed_digest(kind)

    Sandbox.unboxed_run(Repo, fn ->
      put_digest_email_channel(conf)
      {:ok, _rule} = Notifications.put_rule(conf, :digest, true)
      record_on(conf, ~U[2026-11-11 10:00:00.000000Z], kind)
    end)

    1..senders
    |> Task.async_stream(
      fn _sender -> Sandbox.unboxed_run(Repo, fn -> Notifications.send_digest(conf, ~D[2026-11-11]) end) end,
      max_concurrency: senders
    )
    |> Enum.each(fn {:ok, :ok} -> :ok end)

    assert_email_sent(subject: "[Imison] Daily summary for 11 Nov 2026")
    refute_email_sent()
    assert [%Delivery{trigger: :digest, status: :sent}] = Sandbox.unboxed_run(Repo, fn -> Repo.all(Delivery) end)
  end

  def report_delivery_insert(_event, _measurements, %{source: "imison_deliveries", query: "INSERT" <> _rest}, test_pid),
    do: send(test_pid, :delivery_insert)

  def report_delivery_insert(_event, _measurements, _metadata, _test_pid), do: :ok

  defp capture_existing_error(name, occurred_at) do
    event = %{new_error_event() | occurred_at: occurred_at}
    Capture.capture(name, event)
    wait_for_worker(name)
    %Error{id: error_id} = recorded_error(event.message)
    %{id: error_id, event: event}
  end

  defp capture_and_set_status(name, status) do
    event = new_error_event()
    Capture.capture(name, event)
    wait_for_worker(name)
    %Error{id: error_id} = recorded_error(event.message)
    {:ok, 1} = Errors.set_status(Imison.config(name), [error_id], status)
    %{id: error_id, event: event}
  end

  defp turn_every_rule_on(name) do
    for trigger <- Rule.triggers() do
      {:ok, _rule} = Notifications.put_rule(Imison.config(name), trigger, true)
    end
  end

  defp start_mailing_imison(opts \\ []) do
    [mailer: Mailer, from: "errors@example.com"]
    |> Keyword.merge(opts)
    |> start_imison()
  end

  defp put_email_channel(name, attrs) do
    {:ok, channel} = Notifications.put_channel(Imison.config(name), Email.type(), attrs)
    channel
  end

  defp capture_new_error(name) do
    %{message: message} = event = new_error_event()
    Capture.capture(name, event)
    message
  end

  defp new_error_event do
    {exception, stacktrace} = raised(unique_message())
    event = Capture.event(%{kind: :error, reason: exception, stacktrace: stacktrace}, %{})
    %{event | kind: "Imison.NotificationsTestError#{System.unique_integer([:positive])}"}
  end

  defp recorded_error(message) do
    Error
    |> from(as: :error)
    |> where([error: error], error.message == ^message)
    |> Repo.one!()
  end

  defp digest_config(opts \\ []) do
    [repo: Repo, username: "admin", password: "secret", mailer: Mailer, from: "errors@example.com"]
    |> Keyword.merge(opts)
    |> Config.new()
  end

  defp put_digest_email_channel(conf) do
    {:ok, channel} =
      Notifications.put_channel(conf, Email.type(), %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    channel
  end

  defp record_on(conf, occurred_at, kind \\ "Imison.DigestError#{System.unique_integer([:positive])}") do
    {:ok, error} =
      Errors.record(conf, %{kind: kind, message: unique_message(), stacktrace: [], occurred_at: occurred_at})

    error
  end

  defp record_again(conf, %Error{} = error, occurred_at) do
    {:ok, _error} =
      Errors.record(conf, %{kind: error.kind, message: error.message, stacktrace: [], occurred_at: occurred_at})
  end

  defp set_regressed_at(%Error{id: error_id}, regressed_at) do
    Error
    |> from(as: :error)
    |> where([error: error], error.id == ^error_id)
    |> Repo.update_all(set: [regressed_at: regressed_at])
  end

  defp clean_up_committed_digest(kind) do
    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Error |> from(as: :error) |> where([error: error], error.kind == ^kind) |> Repo.delete_all()
        Rule |> from(as: :rule) |> where([rule: rule], rule.trigger == :digest) |> Repo.delete_all()

        ChannelSetting
        |> from(as: :channel)
        |> where([channel: channel], channel.type == ^Email.type())
        |> Repo.delete_all()
      end)
    end)
  end

  defp deliveries(error_id) do
    Delivery
    |> from(as: :delivery)
    |> where([delivery: delivery], delivery.error_id == ^error_id)
    |> Repo.all()
  end
end
