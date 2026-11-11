defmodule Imison.Capture.LoggerHandlerTest do
  use Imison.DataCase, async: false

  import ExUnit.CaptureLog
  import Imison.Test.CaptureHelpers

  require Logger

  defmodule IgnoredError do
    @moduledoc false
    defexception [:message]
  end

  defmodule CrashingServer do
    @moduledoc false
    use GenServer

    def init(message), do: {:ok, message}

    def handle_cast(:crash, message), do: raise(message)
  end

  defmodule ArithmeticServer do
    @moduledoc false
    use GenServer

    def init(state), do: {:ok, state}

    def handle_cast({:add, value}, state), do: {:noreply, state + value}
  end

  test "a process that crashes with an exception is recorded with the exception's kind, message and stack trace" do
    name = start_imison()
    message = unique_message()

    capture_log(fn ->
      {:ok, server} = GenServer.start(CrashingServer, message)
      GenServer.cast(server, :crash)
      wait_for_exit(server)
      wait_for_worker(name)
    end)

    assert [%{kind: "RuntimeError", occurrence_count: 1, stacktrace: [frame | _]}] = recorded(message)
    assert frame["module"] == inspect(CrashingServer)
    assert frame["function"] == "handle_cast"
  end

  test "a crashed process's pid is kept in the occurrence's context" do
    name = start_imison()
    message = unique_message()

    {task, _log} =
      with_log(fn ->
        {:ok, task} = Task.start(fn -> raise message end)
        wait_for_exit(task)
        wait_for_worker(name)
        task
      end)

    assert [%{context: %{"metadata" => %{"pid" => pid}}}] = recorded(message)
    assert pid == inspect(task)
  end

  test "a GenServer that crashes on an Erlang error is recorded with the exception it normalises to" do
    name = start_imison()

    capture_log(fn ->
      {:ok, server} = GenServer.start(ArithmeticServer, 1)
      GenServer.cast(server, {:add, :not_a_number})
      wait_for_exit(server)
      wait_for_worker(name)
    end)

    assert [%{kind: "ArithmeticError", stacktrace: stacktrace}] = recorded("bad argument in arithmetic expression")
    assert Enum.any?(stacktrace, &(&1["module"] == inspect(ArithmeticServer)))
  end

  test "a process that throws is recorded with kind throw" do
    name = start_imison()
    value = unique_message()

    capture_log(fn ->
      {:ok, task} = Task.start(fn -> throw(value) end)
      wait_for_exit(task)
      wait_for_worker(name)
    end)

    assert [%{kind: "throw"}] = recorded(inspect(value))
  end

  test "a process that exits abnormally is recorded with kind exit" do
    name = start_imison()
    reason = unique_message()

    capture_log(fn ->
      {:ok, task} = Task.start(fn -> exit(reason) end)
      wait_for_exit(task)
      wait_for_worker(name)
    end)

    assert [%{kind: "exit"}] = recorded(Exception.format_exit(reason))
  end

  test "a request crash logged by Bandit or Cowboy is not recorded, so the Phoenix report is the only one" do
    name = start_imison()
    message = unique_message()
    {exception, stacktrace} = raised(message)

    capture_log(fn ->
      :logger.error("bandit crash", %{domain: [:bandit], crash_reason: {exception, stacktrace}})
      :logger.error("cowboy crash", %{domain: [:cowboy], crash_reason: {exception, stacktrace}})
      wait_for_worker(name)
    end)

    assert recorded(message) == []
  end

  test "a process that crashes with an ignored exception is not recorded" do
    name = start_imison(ignore: [IgnoredError])
    message = unique_message()

    capture_log(fn ->
      {:ok, task} = Task.start(fn -> raise IgnoredError, message end)
      wait_for_exit(task)
      wait_for_worker(name)
    end)

    assert recorded(message) == []
  end

  test "a crash logged by Imison itself is not recorded" do
    name = start_imison()
    message = unique_message()
    {exception, stacktrace} = raised(message)

    capture_log(fn ->
      :logger.error("Imison failed", %{domain: [:imison], crash_reason: {exception, stacktrace}})
      wait_for_worker(name)
    end)

    assert recorded(message) == []
  end

  test "an error logged without a crash is not recorded" do
    name = start_imison()
    message = unique_message()

    capture_log(fn ->
      Logger.error(message)
      wait_for_worker(name)
    end)

    assert recorded(message) == []
  end

  defp wait_for_exit(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end
  end
end
