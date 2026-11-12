defmodule Imison.Notifications.DigestTest do
  use Imison.DataCase, async: false

  import ExUnit.CaptureLog
  import Imison.Test.CaptureHelpers
  import Swoosh.TestAssertions

  alias Imison.Config
  alias Imison.Errors
  alias Imison.Notifications
  alias Imison.Notifications.Channels.Email
  alias Imison.Notifications.Delivery
  alias Imison.Notifications.Digest
  alias Imison.Test.Mailer

  defmodule FailingMailer do
    @moduledoc false

    def deliver(_email, _config), do: {:error, :smtp_unavailable}
  end

  defmodule UnavailableRepo do
    @moduledoc false

    def config, do: []

    def one(_queryable, _opts), do: raise(DBConnection.ConnectionError, "connection not available")
  end

  test "a running instance starts a digest process" do
    name = start_imison()

    assert {_pid, _value} = Imison.Registry.lookup(name, Digest)
  end

  test "an instance started with enabled: false starts no digest process" do
    name = start_imison(enabled: false)

    assert Imison.Registry.lookup(name, Digest) == nil
  end

  test "once 08:00 UTC has passed the digest process emails the previous day's digest" do
    set_swoosh_global()
    conf = mailing_config()
    put_email_channel_and_digest_rule(conf)
    record_on(conf, ~U[2026-11-11 10:00:00.000000Z])
    digest = start_digest(conf, ~U[2026-11-12 08:00:00Z])

    wait_for_next_run(digest)

    assert_email_sent(subject: "[Imison] Daily summary for 11 Nov 2026")
    assert [%Delivery{trigger: :digest, period: ~U[2026-11-11 00:00:00Z], status: :sent}] = Repo.all(Delivery)
  end

  test "a digest switched on after the digest process found it off is sent at the next tick, once" do
    set_swoosh_global()
    conf = mailing_config()

    {:ok, _channel} =
      Notifications.put_channel(conf, Email.type(), %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    record_on(conf, ~U[2026-11-11 10:00:00.000000Z])
    digest = start_digest(conf, ~U[2026-11-12 09:00:00Z])
    wait_for_next_run(digest)
    refute_email_sent()

    {:ok, _rule} = Notifications.put_rule(conf, :digest, true)
    wait_for_next_run(digest)
    wait_for_next_run(digest)

    assert_email_sent(subject: "[Imison] Daily summary for 11 Nov 2026")
    refute_email_sent()
  end

  test "before 08:00 UTC the digest process sends nothing" do
    set_swoosh_global()
    conf = mailing_config()
    put_email_channel_and_digest_rule(conf)
    record_on(conf, ~U[2026-11-11 10:00:00.000000Z])
    record_on(conf, ~U[2026-11-10 10:00:00.000000Z])
    digest = start_digest(conf, ~U[2026-11-12 07:59:59Z])

    wait_for_next_run(digest)

    refute_email_sent()
    assert Repo.all(Delivery) == []
  end

  test "the digest process tries to claim a day's digest once however many minutes pass" do
    set_swoosh_global()
    conf = mailing_config()
    put_email_channel_and_digest_rule(conf)
    record_on(conf, ~U[2026-11-11 10:00:00.000000Z])
    handler_id = "imison-digest-test-#{System.unique_integer([:positive])}"
    :ok = :telemetry.attach(handler_id, [:imison, :test, :repo, :query], &__MODULE__.report_delivery_insert/4, self())
    on_exit(fn -> :telemetry.detach(handler_id) end)
    digest = start_digest(conf, ~U[2026-11-12 09:00:00Z])

    wait_for_next_run(digest)
    wait_for_next_run(digest)
    wait_for_next_run(digest)

    assert_received :delivery_insert
    refute_received :delivery_insert
  end

  test "a database failure while sending the digest is logged under the imison domain and the process runs again" do
    conf = mailing_config(repo: UnavailableRepo)
    digest = start_digest(conf, ~U[2026-11-12 08:00:00Z])

    log =
      capture_log([metadata: [:domain]], fn ->
        wait_for_next_run(digest)
        wait_for_next_run(digest)
        assert Process.alive?(digest)
        stop_supervised!(Digest)
      end)

    assert log =~
             ~r/domain=elixir\.imison \[error\] Imison failed to send the daily digest.*connection not available.*Imison failed to send the daily digest/s
  end

  test "a digest the mailer fails to send leaves the digest process running" do
    conf = mailing_config(mailer: FailingMailer)
    put_email_channel_and_digest_rule(conf)
    record_on(conf, ~U[2026-11-11 10:00:00.000000Z])
    digest = start_digest(conf, ~U[2026-11-12 08:00:00Z])

    capture_log(fn ->
      wait_for_next_run(digest)
      wait_for_next_run(digest)
    end)

    assert Process.alive?(digest)
    assert [%Delivery{trigger: :digest, status: :failed}] = Repo.all(Delivery)
  end

  def report_delivery_insert(_event, _measurements, %{source: "imison_deliveries", query: "INSERT" <> _rest}, test_pid),
    do: send(test_pid, :delivery_insert)

  def report_delivery_insert(_event, _measurements, _metadata, _test_pid), do: :ok

  defp start_digest(conf, now) do
    start_supervised!({Digest, conf: conf, initial_delay: 0, interval: 10, now: fn -> now end})
  end

  defp wait_for_next_run(digest) do
    :erlang.trace(digest, true, [:receive])

    receive do
      {:trace, ^digest, :receive, :send_digest} -> :ok
    end

    :erlang.trace(digest, false, [:receive])
    :sys.get_state(digest)
  end

  defp mailing_config(opts \\ []) do
    [name: make_ref(), repo: Repo, username: "admin", password: "secret", mailer: Mailer, from: "errors@example.com"]
    |> Keyword.merge(opts)
    |> Config.new()
  end

  defp put_email_channel_and_digest_rule(conf) do
    {:ok, _channel} =
      Notifications.put_channel(conf, Email.type(), %{enabled: true, config: %{"recipients" => ["ops@example.com"]}})

    {:ok, _rule} = Notifications.put_rule(conf, :digest, true)
  end

  defp record_on(conf, occurred_at) do
    {:ok, _error} =
      Errors.record(conf, %{
        kind: "Imison.DigestTestError#{System.unique_integer([:positive])}",
        message: unique_message(),
        stacktrace: [],
        occurred_at: occurred_at
      })
  end
end
