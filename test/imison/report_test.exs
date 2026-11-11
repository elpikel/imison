defmodule Imison.ReportTest do
  use Imison.DataCase, async: false

  import ExUnit.CaptureLog
  import Imison.Test.CaptureHelpers

  test "a reported exception is recorded with its kind, message, stack trace and metadata" do
    start_imison(name: Imison)
    message = unique_message()

    assert place_order(message, %{order_id: 42}) == :ok

    wait_for_worker(Imison)
    assert [%{kind: "RuntimeError", context: context, stacktrace: [frame | _]}] = recorded(message)
    assert context == %{"metadata" => %{"order_id" => 42}}
    assert frame["module"] == inspect(__MODULE__)
    assert frame["function"] == "place_order"
  end

  test "metadata given as a keyword list is recorded as a map" do
    start_imison(name: Imison)
    message = unique_message()

    place_order(message, order_id: 42, step: "payment")

    wait_for_worker(Imison)
    assert [%{context: %{"metadata" => %{"order_id" => 42, "step" => "payment"}}}] = recorded(message)
  end

  test "a token nested in reported metadata is stored as filtered" do
    start_imison(name: Imison)
    message = unique_message()

    place_order(message, %{payment: %{provider: "stripe", token: "tok_123"}})

    wait_for_worker(Imison)
    assert [%{context: %{"metadata" => %{"payment" => payment}}}] = recorded(message)
    assert payment == %{"provider" => "stripe", "token" => "[FILTERED]"}
  end

  test "an exception reported without metadata is recorded" do
    start_imison(name: Imison)
    message = unique_message()
    {exception, stacktrace} = raised(message)

    assert Imison.report(exception, stacktrace) == :ok

    wait_for_worker(Imison)
    assert [%{kind: "RuntimeError", occurrence_count: 1}] = recorded(message)
  end

  test "a reported Erlang error is recorded as its normalized exception" do
    start_imison(name: Imison)

    Imison.report(:badarith, [])

    wait_for_worker(Imison)
    assert [%{kind: "ArithmeticError"}] = recorded("bad argument in arithmetic expression")
  end

  test "reporting with no instance running returns ok and records nothing" do
    message = unique_message()
    {exception, stacktrace} = raised(message)

    assert Imison.report(exception, stacktrace, %{order_id: 42}) == :ok

    assert recorded(message) == []
  end

  test "reporting with metadata that is neither a map nor a keyword list returns ok, logs the failure and records nothing" do
    start_imison(name: Imison)
    message = unique_message()
    {exception, stacktrace} = raised(message)

    log =
      capture_log([metadata: [:domain]], fn ->
        assert Imison.report(exception, stacktrace, "order 42") == :ok
      end)

    wait_for_worker(Imison)
    assert log =~ "Imison failed to report an exception"
    assert log =~ "domain=elixir.imison"
    refute log =~ "order 42"
    assert recorded(message) == []
  end

  test "a reported exception listed in ignore is not recorded" do
    start_imison(name: Imison, ignore: [ArgumentError])
    message = unique_message()

    Imison.report(%ArgumentError{message: message}, [])

    wait_for_worker(Imison)
    assert recorded(message) == []
  end

  defp place_order(message, metadata) do
    raise message
  rescue
    exception -> Imison.report(exception, __STACKTRACE__, metadata)
  end
end
