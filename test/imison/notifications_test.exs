defmodule Imison.NotificationsTest do
  use Imison.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  import Imison.Test.CaptureHelpers
  import Swoosh.TestAssertions

  alias Imison.Capture
  alias Imison.Errors
  alias Imison.Errors.Error
  alias Imison.Notifications
  alias Imison.Notifications.Channels.Email
  alias Imison.Notifications.Delivery
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

  test "another occurrence of an existing error sends no email" do
    set_swoosh_global()
    name = start_mailing_imison()
    put_email_channel(name, %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})
    event = new_error_event()
    Capture.capture(name, event)
    wait_for_worker(name)
    assert_email_sent()

    Capture.capture(name, %{event | occurred_at: DateTime.utc_now()})

    wait_for_worker(name)
    refute_email_sent()
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

  defp capture_and_set_status(name, status) do
    event = new_error_event()
    Capture.capture(name, event)
    wait_for_worker(name)
    %Error{id: error_id} = recorded_error(event.message)
    {:ok, 1} = Errors.set_status(Imison.config(name), [error_id], status)
    %{id: error_id, event: event}
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

  defp deliveries(error_id) do
    Delivery
    |> from(as: :delivery)
    |> where([delivery: delivery], delivery.error_id == ^error_id)
    |> Repo.all()
  end
end
