defmodule Imison.Notifications.NotifierTest do
  use Imison.DataCase, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Imison.Config
  alias Imison.Errors
  alias Imison.Errors.Error
  alias Imison.Notifications
  alias Imison.Notifications.Channel
  alias Imison.Notifications.ChannelSetting
  alias Imison.Notifications.Delivery
  alias Imison.Notifications.Message
  alias Imison.Notifications.Notifier
  alias Imison.Notifications.Rule

  defmodule AcceptingChannel do
    @moduledoc false

    @behaviour Channel

    @impl Channel
    def type, do: "notifier_test"

    @impl Channel
    def validate_config(_channel_config), do: :ok

    @impl Channel
    def deliver(%Message{trigger: trigger}, _channel_config, _conf) do
      if test = Process.whereis(Imison.Notifications.NotifierTest), do: send(test, {:delivered, trigger})
      :ok
    end
  end

  test "processes on their own connections recording the first occurrences of an error at once send exactly one new notification" do
    conf = config()
    kind = "Imison.NotifierNewError#{System.unique_integer([:positive])}"
    recorders = 20
    clean_up_after_test(kind)
    put_accepting_channel(conf)

    flags = record_and_notify_concurrently(conf, %{kind: kind, recorders: recorders})

    assert Enum.count(flags, & &1.created) == 1
    assert deliveries_by_trigger(kind) == %{new: 1}
  end

  test "processes on their own connections recording a resolved error at once send exactly one regression notification" do
    conf = config()
    kind = "Imison.NotifierRegressionError#{System.unique_integer([:positive])}"
    recorders = 20
    clean_up_after_test(kind)
    put_accepting_channel(conf)

    Sandbox.unboxed_run(Repo, fn ->
      {:ok, error} = Errors.record(conf, occurrence(kind))
      Notifications.notify(conf, error, :new)
      {:ok, 1} = Errors.set_status(conf, [error.id], :resolved)
    end)

    flags = record_and_notify_concurrently(conf, %{kind: kind, recorders: recorders})

    assert Enum.count(flags, & &1.reopened) == 1
    assert deliveries_by_trigger(kind) == %{new: 1, regression: 1}
  end

  test "processes on their own connections recording one unresolved error in the same hour at once send exactly one still happening reminder" do
    Process.register(self(), __MODULE__)
    conf = config()
    kind = "Imison.NotifierStillHappeningError#{System.unique_integer([:positive])}"
    recorders = 20
    clean_up_after_test(kind)
    put_accepting_channel(conf)
    turn_rule_on_until_test_ends(conf, :still_happening)
    Sandbox.unboxed_run(Repo, fn -> {:ok, _error} = Errors.record(conf, occurrence(kind)) end)

    record_and_notify_concurrently(conf, %{kind: kind, recorders: recorders})

    assert deliveries_by_trigger(kind) == %{still_happening: 1}
    assert delivered_triggers() == [:still_happening]
  end

  test "processes on their own connections claiming the digest of one channel and day at once leave exactly one claim" do
    conf = config()
    claimers = 20
    delete_channel_after_test()
    channel = put_accepting_channel(conf)
    period = ~U[2026-11-12 00:00:00Z]

    claims =
      1..claimers
      |> Task.async_stream(
        fn _claimer ->
          Sandbox.unboxed_run(Repo, fn ->
            Notifications.claim_delivery(conf, %{channel_id: channel.id, error_id: nil, trigger: :digest, period: period})
          end)
        end,
        max_concurrency: claimers
      )
      |> Enum.map(fn {:ok, claim} -> claim end)

    assert Enum.count(claims, &match?({:ok, %Delivery{}}, &1)) == 1
    assert Enum.count(claims, &(&1 == :already_claimed)) == claimers - 1

    assert [%Delivery{error_id: nil, trigger: :digest, period: ^period, status: :pending}] =
             Sandbox.unboxed_run(Repo, fn ->
               Delivery
               |> from(as: :delivery)
               |> where([delivery: delivery], delivery.channel_id == ^channel.id)
               |> Repo.all()
             end)
  end

  test "a reminder whose hour another node already claimed does not call the channel" do
    Process.register(self(), __MODULE__)
    conf = config()
    {:ok, channel} = Notifications.put_channel(conf, AcceptingChannel.type(), %{enabled: true, config: %{}})
    {:ok, _rule} = Notifications.put_rule(conf, :still_happening, true)
    {:ok, error} = Errors.record(conf, occurrence("Imison.NotifierClaimedReminder"))
    period = Delivery.period(:still_happening, error.last_seen_at)

    {:ok, _claim} =
      Notifications.claim_delivery(conf, %{
        channel_id: channel.id,
        error_id: error.id,
        trigger: :still_happening,
        period: period
      })

    :ok = Notifications.notify(conf, error, :still_happening)

    assert delivered_triggers() == []

    assert [%Delivery{period: ^period, status: :pending}] =
             Delivery
             |> from(as: :delivery)
             |> where([delivery: delivery], delivery.channel_id == ^channel.id)
             |> Repo.all()
  end

  defp record_and_notify_concurrently(conf, %{kind: kind, recorders: recorders}) do
    1..recorders
    |> Task.async_stream(
      fn _recorder ->
        Sandbox.unboxed_run(Repo, fn ->
          {:ok, error} = Errors.record(conf, occurrence(kind))
          error |> Notifier.triggers() |> Enum.each(&Notifications.notify(conf, error, &1))
          %{created: error.created, reopened: error.reopened}
        end)
      end,
      max_concurrency: recorders
    )
    |> Enum.map(fn {:ok, flags} -> flags end)
  end

  defp deliveries_by_trigger(kind) do
    Sandbox.unboxed_run(Repo, fn ->
      Delivery
      |> from(as: :delivery)
      |> join(:inner, [delivery: delivery], error in Error, on: error.id == delivery.error_id, as: :error)
      |> where([error: error], error.kind == ^kind)
      |> group_by([delivery: delivery], delivery.trigger)
      |> select([delivery: delivery], {delivery.trigger, count(delivery.id)})
      |> Repo.all()
      |> Map.new()
    end)
  end

  defp delivered_triggers(triggers \\ []) do
    receive do
      {:delivered, trigger} -> delivered_triggers([trigger | triggers])
    after
      0 -> Enum.reverse(triggers)
    end
  end

  defp put_accepting_channel(conf) do
    Sandbox.unboxed_run(Repo, fn ->
      {:ok, channel} = Notifications.put_channel(conf, AcceptingChannel.type(), %{enabled: true, config: %{}})
      channel
    end)
  end

  defp turn_rule_on_until_test_ends(conf, trigger) do
    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Rule |> from(as: :rule) |> where([rule: rule], rule.trigger == ^trigger) |> Repo.delete_all()
      end)
    end)

    Sandbox.unboxed_run(Repo, fn -> {:ok, _rule} = Notifications.put_rule(conf, trigger, true) end)
  end

  defp clean_up_after_test(kind) do
    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Error |> from(as: :error) |> where([error: error], error.kind == ^kind) |> Repo.delete_all()
      end)
    end)

    delete_channel_after_test()
  end

  defp delete_channel_after_test do
    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        ChannelSetting
        |> from(as: :channel)
        |> where([channel: channel], channel.type == ^AcceptingChannel.type())
        |> Repo.delete_all()
      end)
    end)
  end

  defp config do
    Config.new(repo: Repo, username: "admin", password: "secret", channels: [AcceptingChannel])
  end

  defp occurrence(kind) do
    %{
      kind: kind,
      message: "boom",
      stacktrace: [],
      context: %{},
      release: "1.0.0",
      occurred_at: ~U[2026-11-12 10:15:00.000000Z]
    }
  end
end
