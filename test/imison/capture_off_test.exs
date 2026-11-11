defmodule Imison.CaptureOffTest do
  use Imison.DataCase, async: false

  import ExUnit.CaptureLog
  import Imison.Test.CaptureHelpers

  alias Imison.Capture.Worker
  alias Imison.Config

  test "an instance started with enabled: false attaches no logger or telemetry handler" do
    name = start_imison(enabled: false)

    assert attached_handlers(name) == %{logger: [], telemetry: []}
  end

  test "a process that crashes while capture is off is not recorded" do
    start_imison(name: Imison, enabled: false)
    message = unique_message()

    capture_log(fn ->
      {:ok, task} = Task.start(fn -> raise message end)
      wait_for_exit(task)
    end)

    assert Imison.Registry.lookup(Imison, Worker) == nil
    assert recorded(message) == []
  end

  test "a Phoenix request exception while capture is off is not recorded" do
    start_imison(name: Imison, enabled: false)
    message = unique_message()
    {exception, stacktrace} = raised(message)

    :telemetry.execute([:phoenix, :router_dispatch, :exception], %{duration: 1_000}, %{
      conn: Plug.Test.conn(:get, "/orders"),
      kind: :error,
      reason: exception,
      stacktrace: stacktrace
    })

    assert Imison.Registry.lookup(Imison, Worker) == nil
    assert recorded(message) == []
  end

  test "an Oban job exception while capture is off is not recorded" do
    start_imison(name: Imison, enabled: false)
    message = unique_message()
    {exception, stacktrace} = raised(message)

    :telemetry.execute([:oban, :job, :exception], %{duration: 1_000, queue_time: 500}, %{
      job: %{worker: "MyApp.Workers.SendInvoice", queue: "mailers", args: %{}, attempt: 1},
      kind: :error,
      reason: exception,
      stacktrace: stacktrace,
      state: :failure
    })

    assert Imison.Registry.lookup(Imison, Worker) == nil
    assert recorded(message) == []
  end

  test "reporting an exception while capture is off returns ok and records nothing" do
    start_imison(name: Imison, enabled: false)
    message = unique_message()
    {exception, stacktrace} = raised(message)

    assert Imison.report(exception, stacktrace, %{order_id: 42}) == :ok

    assert Imison.Registry.lookup(Imison, Worker) == nil
    assert recorded(message) == []
  end

  test "the config of an instance started with enabled: false is still readable" do
    start_imison(name: Imison, enabled: false)

    assert %Config{name: Imison, repo: Repo, enabled: false} = Imison.config()
  end
end
