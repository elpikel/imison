defmodule Imison.ErrorsTest do
  use Imison.DataCase, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Imison.Config
  alias Imison.Errors
  alias Imison.Errors.Error
  alias Imison.Errors.HourlyCount
  alias Imison.Errors.Occurrence
  alias Imison.Test.PrivatePrefix

  test "two occurrences of the same bug with different messages are one error with two occurrences" do
    conf = config()

    {:ok, first} = Errors.record(conf, occurrence(message: "order 1 not found"))
    {:ok, second} = Errors.record(conf, occurrence(message: "order 2 not found"))

    assert first.id == second.id
    assert %Error{occurrence_count: 2} = Repo.get!(Error, first.id)

    assert Occurrence
           |> from(as: :occurrence)
           |> where([occurrence: occurrence], occurrence.error_id == ^first.id)
           |> Repo.aggregate(:count) == 2
  end

  test "the hourly count follows the occurrences of each hour" do
    conf = config()

    {:ok, error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-11 10:05:00.000000Z]))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-11 10:55:00.000000Z]))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-11 11:10:00.000000Z]))

    hourly_counts =
      HourlyCount
      |> from(as: :hourly_count)
      |> where([hourly_count: hourly_count], hourly_count.error_id == ^error.id)
      |> order_by([hourly_count: hourly_count], hourly_count.hour)
      |> select([hourly_count: hourly_count], %{hour: hourly_count.hour, count: hourly_count.count})
      |> Repo.all()

    assert hourly_counts == [
             %{hour: ~U[2026-11-11 10:00:00Z], count: 2},
             %{hour: ~U[2026-11-11 11:00:00Z], count: 1}
           ]
  end

  test "hourly counts cover the 24 hours ending with the current hour, oldest first, with zeros for quiet hours" do
    conf = config()
    now = ~U[2026-11-11 14:35:00.000000Z]

    {:ok, error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-10 15:59:00.000000Z]))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-11 09:10:00.000000Z]))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-11 09:50:00.000000Z]))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-11 14:00:00.000000Z]))

    assert Errors.hourly_counts(conf, [error.id], now) == %{
             error.id => [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 1]
           }
  end

  test "hourly counts leave out hours older than the last 24" do
    conf = config()
    now = ~U[2026-11-11 14:35:00.000000Z]

    {:ok, error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-10 14:59:00.000000Z]))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-09 18:00:00.000000Z]))

    assert Errors.hourly_counts(conf, [error.id], now) == %{error.id => List.duplicate(0, 24)}
  end

  test "hourly counts are kept apart per error" do
    conf = config()
    now = ~U[2026-11-11 14:35:00.000000Z]

    {:ok, busy} = Errors.record(conf, occurrence(kind: "KeyError", occurred_at: ~U[2026-11-11 14:01:00.000000Z]))
    {:ok, _busy} = Errors.record(conf, occurrence(kind: "KeyError", occurred_at: ~U[2026-11-11 14:02:00.000000Z]))
    {:ok, quiet} = Errors.record(conf, occurrence(kind: "ArgumentError", occurred_at: ~U[2026-11-11 13:00:00.000000Z]))

    assert Errors.hourly_counts(conf, [busy.id, quiet.id], now) == %{
             busy.id => [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2],
             quiet.id => [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0]
           }
  end

  test "with a configured prefix the hourly counts are read from that schema" do
    PrivatePrefix.migrate_up()
    conf = config(prefix: PrivatePrefix.name())

    {:ok, error} =
      Errors.record(
        conf,
        occurrence(
          kind: "Imison.PrefixError#{System.unique_integer([:positive])}",
          occurred_at: ~U[2026-11-11 14:10:00.000000Z]
        )
      )

    assert Errors.hourly_counts(conf, [error.id], ~U[2026-11-11 14:35:00.000000Z]) == %{
             error.id => [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
           }
  end

  test "the same kind raised from different application frames is two errors" do
    conf = config()

    {:ok, first} = Errors.record(conf, occurrence(stacktrace: [application_frame(Config, :new, 1)]))
    {:ok, second} = Errors.record(conf, occurrence(stacktrace: [application_frame(Imison.Migration, :up, 1)]))

    assert first.id != second.id
  end

  test "different kinds raised from the same application frame are two errors" do
    conf = config()

    {:ok, first} = Errors.record(conf, occurrence(kind: "RuntimeError"))
    {:ok, second} = Errors.record(conf, occurrence(kind: "ArgumentError"))

    assert first.id != second.id
  end

  test "different dependency frames above the same application frame are one error" do
    conf = config()
    application_frame = application_frame(Config, :new, 1)

    {:ok, first} =
      Errors.record(conf, occurrence(stacktrace: [dependency_frame(Ecto.Repo, :insert, 2), application_frame]))

    {:ok, second} =
      Errors.record(conf, occurrence(stacktrace: [dependency_frame(Enum, :map, 2), application_frame]))

    assert first.id == second.id
    assert %Error{occurrence_count: 2} = Repo.get!(Error, first.id)
  end

  test "with no application frame occurrences are grouped by kind and first frame, which is the location" do
    conf = config()
    first_frame = {Ecto.Repo, :insert, 2, [file: ~c"lib/ecto/repo.ex", line: 7]}

    {:ok, first} =
      Errors.record(conf, occurrence(stacktrace: [first_frame, dependency_frame(Enum, :map, 2)]))

    {:ok, second} =
      Errors.record(conf, occurrence(stacktrace: [first_frame, dependency_frame(Enum, :each, 2)]))

    {:ok, other} =
      Errors.record(conf, occurrence(stacktrace: [dependency_frame(Enum, :each, 2), first_frame]))

    assert first.id == second.id
    assert other.id != first.id
    assert second.location == "Ecto.Repo.insert/2 (lib/ecto/repo.ex:7)"
  end

  test "an error shows its latest occurrence's message and last seen time and keeps its first seen time" do
    conf = config()

    {:ok, error} =
      Errors.record(conf, occurrence(message: "first wording", occurred_at: ~U[2026-11-11 10:00:00.000000Z]))

    {:ok, _error} =
      Errors.record(conf, occurrence(message: "later wording", occurred_at: ~U[2026-11-11 12:30:00.000000Z]))

    assert %Error{
             message: "later wording",
             first_seen_at: ~U[2026-11-11 10:00:00.000000Z],
             last_seen_at: ~U[2026-11-11 12:30:00.000000Z]
           } = Repo.get!(Error, error.id)
  end

  test "an earlier occurrence recorded after a later one keeps the later message and last seen time" do
    conf = config()

    {:ok, error} =
      Errors.record(conf, occurrence(message: "later wording", occurred_at: ~U[2026-11-11 12:30:00.000000Z]))

    {:ok, _error} =
      Errors.record(conf, occurrence(message: "earlier wording", occurred_at: ~U[2026-11-11 10:00:00.000000Z]))

    assert %Error{
             message: "later wording",
             last_seen_at: ~U[2026-11-11 12:30:00.000000Z],
             occurrence_count: 2
           } = Repo.get!(Error, error.id)
  end

  test "with no application frame and an Erlang built-in on top, that built-in groups the error and is its location" do
    conf = config()
    builtin_frame = {:erlang, :+, [1, :a], [error_info: %{module: :erl_erts_errors}]}

    {:ok, first} =
      Errors.record(
        conf,
        occurrence(kind: "ArithmeticError", stacktrace: [builtin_frame, dependency_frame(Enum, :map, 2)])
      )

    {:ok, second} =
      Errors.record(
        conf,
        occurrence(kind: "ArithmeticError", stacktrace: [builtin_frame, dependency_frame(Enum, :each, 2)])
      )

    {:ok, other_kind} = Errors.record(conf, occurrence(kind: "ArgumentError", stacktrace: [builtin_frame]))

    assert first.id == second.id
    assert other_kind.id != first.id
    assert first.location == ":erlang.+/2"

    assert [%Occurrence{stacktrace: [stored_builtin_frame, _dependency_frame]} | _occurrences] =
             Occurrence
             |> from(as: :occurrence)
             |> where([occurrence: occurrence], occurrence.error_id == ^first.id)
             |> Repo.all()

    assert stored_builtin_frame == %{
             "module" => ":erlang",
             "function" => "+",
             "arity" => 2,
             "file" => nil,
             "line" => nil,
             "application" => false
           }
  end

  test "an occurrence with an empty stack trace is grouped by its kind alone and has no location" do
    conf = config()

    {:ok, first} = Errors.record(conf, occurrence(kind: "RuntimeError", stacktrace: []))
    {:ok, second} = Errors.record(conf, occurrence(kind: "RuntimeError", stacktrace: []))
    {:ok, other_kind} = Errors.record(conf, occurrence(kind: "ArgumentError", stacktrace: []))

    assert first.id == second.id
    assert other_kind.id != first.id
    assert %Error{location: nil, occurrence_count: 2} = Repo.get!(Error, first.id)
  end

  test "the location is the first application frame with its file and line" do
    conf = config()

    stacktrace = [
      dependency_frame(Ecto.Repo, :insert, 2),
      {Config, :new, 1, [file: ~c"lib/imison/config.ex", line: 42]},
      application_frame(Imison.Migration, :up, 1)
    ]

    {:ok, error} = Errors.record(conf, occurrence(stacktrace: stacktrace))

    assert error.location == "Imison.Config.new/1 (lib/imison/config.ex:42)"
  end

  test "the stored stack trace keeps each frame's module, function, arity, file, line and application marking but not its arguments" do
    conf = config()
    frame_with_arguments = {Config, :new, [[password: "secret"]], [file: ~c"lib/imison/config.ex", line: 42]}

    {:ok, error} = Errors.record(conf, occurrence(stacktrace: [frame_with_arguments]))

    assert [%Occurrence{stacktrace: stacktrace}] =
             Occurrence
             |> from(as: :occurrence)
             |> where([occurrence: occurrence], occurrence.error_id == ^error.id)
             |> Repo.all()

    assert stacktrace == [
             %{
               "module" => "Imison.Config",
               "function" => "new",
               "arity" => 1,
               "file" => "lib/imison/config.ex",
               "line" => 42,
               "application" => true
             }
           ]
  end

  test "each stored frame is marked as an application frame when its module belongs to the repo's OTP app" do
    conf = config()

    stacktrace = [
      dependency_frame(Ecto.Repo, :insert, 2),
      application_frame(Config, :new, 1),
      dependency_frame(Enum, :map, 2),
      application_frame(Imison.Migration, :up, 1)
    ]

    {:ok, error} = Errors.record(conf, occurrence(stacktrace: stacktrace))

    assert [%Occurrence{stacktrace: stored_frames}] =
             Occurrence
             |> from(as: :occurrence)
             |> where([occurrence: occurrence], occurrence.error_id == ^error.id)
             |> Repo.all()

    assert Enum.map(stored_frames, &%{module: &1["module"], application: &1["application"]}) == [
             %{module: "Ecto.Repo", application: false},
             %{module: "Imison.Config", application: true},
             %{module: "Enum", application: false},
             %{module: "Imison.Migration", application: true}
           ]
  end

  test "processes on their own connections recording the same error at once sum every occurrence" do
    conf = config()
    kind = "Imison.ConcurrentError#{System.unique_integer([:positive])}"
    occurred_at = ~U[2026-11-11 10:15:00.000000Z]
    recorders = 20

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Error |> from(as: :error) |> where([error: error], error.kind == ^kind) |> Repo.delete_all()
      end)
    end)

    1..recorders
    |> Task.async_stream(
      fn _recorder ->
        Sandbox.unboxed_run(Repo, fn -> Errors.record(conf, occurrence(kind: kind, occurred_at: occurred_at)) end)
      end,
      max_concurrency: recorders
    )
    |> Stream.run()

    assert [%{occurrence_count: ^recorders, hourly_count: ^recorders}] =
             Sandbox.unboxed_run(Repo, fn ->
               Error
               |> from(as: :error)
               |> join(:inner, [error: error], hourly_count in HourlyCount,
                 on: hourly_count.error_id == error.id,
                 as: :hourly_count
               )
               |> where([error: error], error.kind == ^kind)
               |> select([error: error, hourly_count: hourly_count], %{
                 occurrence_count: error.occurrence_count,
                 hourly_count: hourly_count.count
               })
               |> Repo.all()
             end)
  end

  test "a resolved error that happens again is unresolved and flagged as a regression with the time it came back" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence([]))
    set_status(error, :resolved)

    before_recording = DateTime.utc_now()
    {:ok, recorded} = Errors.record(conf, occurrence([]))

    assert recorded.reopened
    assert %Error{status: :unresolved, regressed_at: %DateTime{} = regressed_at} = Repo.get!(Error, error.id)
    assert DateTime.compare(regressed_at, before_recording) != :lt
  end

  test "an ignored error that happens again stays ignored, counts the occurrence and is not flagged" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence([]))
    set_status(error, :ignored)

    {:ok, recorded} = Errors.record(conf, occurrence([]))

    refute recorded.reopened
    assert %Error{status: :ignored, regressed_at: nil, occurrence_count: 2} = Repo.get!(Error, error.id)
  end

  test "an unresolved error that was never resolved is not flagged when it happens again" do
    conf = config()
    {:ok, first} = Errors.record(conf, occurrence([]))

    {:ok, recorded} = Errors.record(conf, occurrence([]))

    refute first.reopened
    refute recorded.reopened
    assert %Error{status: :unresolved, regressed_at: nil} = Repo.get!(Error, first.id)
  end

  test "processes on their own connections recording a resolved error at once tell exactly one of them it reopened the error" do
    conf = config()
    kind = "Imison.RegressionError#{System.unique_integer([:positive])}"
    recorders = 20

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Error |> from(as: :error) |> where([error: error], error.kind == ^kind) |> Repo.delete_all()
      end)
    end)

    Sandbox.unboxed_run(Repo, fn ->
      {:ok, error} = Errors.record(conf, occurrence(kind: kind))
      set_status(error, :resolved)
    end)

    regressions =
      1..recorders
      |> Task.async_stream(
        fn _recorder ->
          {:ok, error} = Sandbox.unboxed_run(Repo, fn -> Errors.record(conf, occurrence(kind: kind)) end)
          error.reopened
        end,
        max_concurrency: recorders
      )
      |> Enum.count(&(&1 == {:ok, true}))

    assert regressions == 1
  end

  test "with a configured prefix the error and occurrence are stored in that schema" do
    PrivatePrefix.migrate_up()
    conf = config(prefix: PrivatePrefix.name())

    {:ok, error} = Errors.record(conf, occurrence(kind: "Imison.PrefixError#{System.unique_integer([:positive])}"))

    assert %Error{id: error_id} = Repo.get_by!(Error, [fingerprint: error.fingerprint], prefix: PrivatePrefix.name())
    assert error_id == error.id
    assert [%Occurrence{error_id: ^error_id}] = Repo.all(Occurrence, prefix: PrivatePrefix.name())
    assert Repo.get_by(Error, fingerprint: error.fingerprint) == nil
  end

  defp config(opts \\ []) do
    Config.new([repo: Repo, username: "admin", password: "secret"] ++ opts)
  end

  defp set_status(%Error{id: error_id}, status) do
    Error
    |> from(as: :error)
    |> where([error: error], error.id == ^error_id)
    |> Repo.update_all(set: [status: status])
  end

  defp occurrence(overrides) do
    Map.merge(
      %{
        kind: "RuntimeError",
        message: "boom",
        stacktrace: [dependency_frame(Ecto.Repo, :insert, 2), application_frame(Config, :new, 1)],
        context: %{},
        release: "1.0.0",
        occurred_at: ~U[2026-11-11 10:15:00.000000Z]
      },
      Map.new(overrides)
    )
  end

  defp application_frame(module, function, arity) do
    {module, function, arity, [file: ~c"lib/imison/application_frame.ex", line: 10]}
  end

  defp dependency_frame(module, function, arity) do
    {module, function, arity, [file: ~c"deps/dependency_frame.ex", line: 20]}
  end
end
