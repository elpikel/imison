defmodule Imison.CaptureTest do
  use Imison.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Imison.Capture
  alias Imison.Capture.Worker
  alias Imison.Config
  alias Imison.Errors.Error
  alias Imison.Errors.Occurrence

  test "a captured event is recorded in the background as an occurrence of its error" do
    name = make_ref()
    kind = unique_kind()
    start_supervised!({Imison, name: name, repo: Repo, username: "admin", password: "secret"})

    assert Capture.capture(name, event(kind: kind, message: "order 7 not found")) == :ok

    wait_for_worker(name)
    assert [%{message: "order 7 not found", occurrence_count: 1}] = recorded(kind)
  end

  test "the occurrence of a captured event carries the configured release" do
    name = make_ref()
    kind = unique_kind()
    start_supervised!({Imison, name: name, repo: Repo, username: "admin", password: "secret", release: "2.4.1"})

    Capture.capture(name, event(kind: kind))

    wait_for_worker(name)
    assert [%{release: "2.4.1"}] = recorded(kind)
  end

  test "the occurrence of a captured event carries the name of the node that captured it" do
    name = make_ref()
    kind = unique_kind()
    start_supervised!({Imison, name: name, repo: Repo, username: "admin", password: "secret"})

    Capture.capture(name, event(kind: kind))

    wait_for_worker(name)
    assert [%{context: %{"runtime" => %{"node" => node_name}}}] = recorded(kind)
    assert node_name == Atom.to_string(node())
  end

  test "a runtime given in a captured event's context is replaced by the node that captured it" do
    name = make_ref()
    kind = unique_kind()
    start_supervised!({Imison, name: name, repo: Repo, username: "admin", password: "secret"})

    Capture.capture(name, event(kind: kind, context: %{runtime: %{node: "spoofed@host"}, metadata: %{step: "payment"}}))

    wait_for_worker(name)
    assert [%{context: context}] = recorded(kind)
    assert context == %{"runtime" => %{"node" => Atom.to_string(node())}, "metadata" => %{"step" => "payment"}}
  end

  test "events captured while the worker's queue is full are dropped and counted" do
    name = make_ref()
    kind = unique_kind()
    conf = Config.new(name: name, repo: Repo, username: "admin", password: "secret")
    worker = start_supervised!({Worker, conf: conf, queue_limit: 2})

    :sys.suspend(worker)
    Enum.each(1..5, fn _event -> Capture.capture(name, event(kind: kind)) end)
    :sys.resume(worker)

    wait_for_worker(name)
    assert Capture.dropped(name) == 3
    assert [%{occurrence_count: 2}] = recorded(kind)
  end

  test "capturing with no instance running under the name returns without recording anything" do
    kind = unique_kind()

    assert Capture.capture(make_ref(), event(kind: kind)) == :ok

    assert recorded(kind) == []
  end

  test "an event that fails to record is logged under the imison domain, not recorded, and the next event is still recorded" do
    name = make_ref()
    failing_kind = unique_kind()
    kind = unique_kind()
    start_supervised!({Imison, name: name, repo: Repo, username: "admin", password: "secret"})

    log =
      capture_log([metadata: [:domain]], fn ->
        Capture.capture(name, event(kind: failing_kind, occurred_at: "not a time"))
        Capture.capture(name, event(kind: kind))
        wait_for_worker(name)
      end)

    assert log =~ ~r/domain=elixir\.imison \[error\] Imison failed to record a captured event/
    assert recorded(failing_kind) == []
    assert [%{occurrence_count: 1}] = recorded(kind)
  end

  test "a broadcast that fails is logged and the event is still recorded" do
    name = make_ref()
    kind = unique_kind()

    start_supervised!(
      {Imison, name: name, repo: Repo, username: "admin", password: "secret", pubsub: Imison.Test.MissingPubSub}
    )

    log =
      capture_log([metadata: [:domain]], fn ->
        Capture.capture(name, event(kind: kind))
        wait_for_worker(name)
      end)

    assert log =~ ~r/domain=elixir\.imison \[error\] Imison failed to broadcast a recorded error/
    assert [%{occurrence_count: 1}] = recorded(kind)
  end

  test "the dropped count is zero when no instance runs under the name" do
    assert Capture.dropped(make_ref()) == 0
  end

  defp wait_for_worker(name) do
    name
    |> Imison.Registry.via(Worker)
    |> :sys.get_state()
  end

  defp recorded(kind) do
    Error
    |> from(as: :error)
    |> join(:inner, [error: error], occurrence in Occurrence, on: occurrence.error_id == error.id, as: :occurrence)
    |> where([error: error], error.kind == ^kind)
    |> select([error: error, occurrence: occurrence], %{
      message: error.message,
      occurrence_count: error.occurrence_count,
      release: occurrence.release,
      context: occurrence.context
    })
    |> distinct(true)
    |> Repo.all()
  end

  defp unique_kind, do: "Imison.CaptureError#{System.unique_integer([:positive])}"

  defp event(overrides) do
    Map.merge(
      %{
        kind: "RuntimeError",
        message: "boom",
        stacktrace: [{Config, :new, 1, [file: ~c"lib/imison/config.ex", line: 10]}],
        context: %{},
        occurred_at: ~U[2026-11-11 10:15:00.000000Z]
      },
      Map.new(overrides)
    )
  end
end
