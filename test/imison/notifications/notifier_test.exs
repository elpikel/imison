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
  alias Imison.Notifications.Notifier

  defmodule AcceptingChannel do
    @moduledoc false

    @behaviour Channel

    @impl Channel
    def type, do: "notifier_test"

    @impl Channel
    def validate_config(_channel_config), do: :ok

    @impl Channel
    def deliver(_message, _channel_config, _conf), do: :ok
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

  defp put_accepting_channel(conf) do
    Sandbox.unboxed_run(Repo, fn ->
      {:ok, _channel} = Notifications.put_channel(conf, AcceptingChannel.type(), %{enabled: true, config: %{}})
    end)
  end

  defp clean_up_after_test(kind) do
    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Error |> from(as: :error) |> where([error: error], error.kind == ^kind) |> Repo.delete_all()

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
