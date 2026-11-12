defmodule Imison.ErrorsTest do
  use Imison.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog

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

  test "an occurrence is given with its position among the error's occurrences by time and its older and newer neighbours" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-11 12:00:00.000000Z]))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-11 10:00:00.000000Z]))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-11 11:00:00.000000Z]))
    [oldest_id, middle_id, latest_id] = occurrence_ids_oldest_first(error)

    assert %{occurrence: %Occurrence{id: ^middle_id}, position: 2, total: 3} =
             Errors.occurrence(conf, error.id, middle_id)

    assert %{older_id: ^oldest_id, newer_id: ^latest_id} = Errors.occurrence(conf, error.id, middle_id)
  end

  test "without an occurrence id the error's latest occurrence is given, with no newer neighbour" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-11 12:00:00.000000Z]))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-11 10:00:00.000000Z]))
    [oldest_id, latest_id] = occurrence_ids_oldest_first(error)

    assert %{occurrence: %Occurrence{id: ^latest_id}, position: 2, total: 2, older_id: ^oldest_id, newer_id: nil} =
             Errors.occurrence(conf, error.id, nil)
  end

  test "the oldest occurrence has no older neighbour" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-11 10:00:00.000000Z]))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-11 12:00:00.000000Z]))
    [oldest_id, latest_id] = occurrence_ids_oldest_first(error)

    assert %{occurrence: %Occurrence{id: ^oldest_id}, position: 1, total: 2, older_id: nil, newer_id: ^latest_id} =
             Errors.occurrence(conf, error.id, Integer.to_string(oldest_id))
  end

  test "occurrences at the same time are ordered by id, the later recorded being the newer" do
    conf = config()
    same_time = ~U[2026-11-11 10:00:00.000000Z]
    {:ok, error} = Errors.record(conf, occurrence(occurred_at: same_time))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: same_time))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: same_time))
    [first_id, second_id, third_id] = occurrence_ids_oldest_first(error)

    assert %{occurrence: %Occurrence{id: ^third_id}, position: 3} = Errors.occurrence(conf, error.id, nil)

    assert %{position: 2, older_id: ^first_id, newer_id: ^third_id} =
             Errors.occurrence(conf, error.id, second_id)
  end

  test "an occurrence id of another error, or one that is not an id, gives the error's latest occurrence" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-11 10:00:00.000000Z]))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-11 12:00:00.000000Z]))
    {:ok, other_error} = Errors.record(conf, occurrence(kind: "KeyError"))
    [other_occurrence_id] = occurrence_ids_oldest_first(other_error)
    [_oldest_id, latest_id] = occurrence_ids_oldest_first(error)

    for occurrence_id <- [other_occurrence_id, "abc", "12abc", "99999999999999999999", -1] do
      assert %{occurrence: %Occurrence{id: ^latest_id}, position: 2, total: 2} =
               Errors.occurrence(conf, error.id, occurrence_id)
    end
  end

  test "an error whose occurrences were all pruned has no occurrence" do
    conf = config(retention_days: 7)
    {:ok, error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-01 10:00:00.000000Z]))
    Errors.prune(conf, ~U[2026-11-12 12:00:00.000000Z])

    assert Errors.occurrence(conf, error.id, nil) == nil
  end

  test "with a configured prefix occurrences are read from that schema" do
    PrivatePrefix.migrate_up()
    conf = config(prefix: PrivatePrefix.name())
    kind = "Imison.PrefixError#{System.unique_integer([:positive])}"
    {:ok, error} = Errors.record(conf, occurrence(kind: kind, occurred_at: ~U[2026-11-11 10:00:00.000000Z]))
    {:ok, _error} = Errors.record(conf, occurrence(kind: kind, occurred_at: ~U[2026-11-11 12:00:00.000000Z]))
    [oldest_id, latest_id] = Occurrence |> Repo.all(prefix: PrivatePrefix.name()) |> Enum.map(& &1.id) |> Enum.sort()

    assert %{occurrence: %Occurrence{id: ^latest_id}, position: 2, total: 2, older_id: ^oldest_id} =
             Errors.occurrence(conf, error.id, nil)
  end

  test "setting a status stores it on the given errors and leaves the others as they were" do
    conf = config()
    {:ok, first} = Errors.record(conf, occurrence(kind: "KeyError"))
    {:ok, second} = Errors.record(conf, occurrence(kind: "ArgumentError"))
    {:ok, untouched} = Errors.record(conf, occurrence(kind: "MatchError"))

    assert Errors.set_status(conf, [first.id, second.id], :resolved) == {:ok, 2}

    assert %Error{status: :resolved} = Repo.get!(Error, first.id)
    assert %Error{status: :resolved} = Repo.get!(Error, second.id)
    assert %Error{status: :unresolved} = Repo.get!(Error, untouched.id)
  end

  test "a status given as text is stored like the same status given as an atom" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence([]))

    assert Errors.set_status(conf, [error.id], "ignored") == {:ok, 1}

    assert %Error{status: :ignored} = Repo.get!(Error, error.id)
  end

  test "an unknown status is rejected and no error changes" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence([]))

    assert Errors.set_status(conf, [error.id], "deleted") == {:error, :invalid_status}
    assert Errors.set_status(conf, [error.id], :deleted) == {:error, :invalid_status}

    assert %Error{status: :unresolved} = Repo.get!(Error, error.id)
  end

  test "ids given as text are read as error ids and anything that is not an error id is skipped" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence([]))

    assert Errors.set_status(conf, [Integer.to_string(error.id), "abc", "9223372036854775808", -1, nil], :resolved) ==
             {:ok, 1}

    assert %Error{status: :resolved} = Repo.get!(Error, error.id)
  end

  test "a status change moves the error's updated_at forward even when it is ahead of the clock" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence([]))
    ahead_of_the_clock = DateTime.shift(DateTime.utc_now(), hour: 1)
    set_updated_at(error, ahead_of_the_clock)

    {:ok, 1} = Errors.set_status(conf, [error.id], :resolved)

    assert DateTime.after?(Repo.get!(Error, error.id).updated_at, ahead_of_the_clock)
  end

  test "an error resolved by a status change is reopened by its next occurrence" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence([]))
    {:ok, 1} = Errors.set_status(conf, [error.id], :resolved)

    {:ok, recorded} = Errors.record(conf, occurrence([]))

    assert recorded.reopened
    assert %Error{status: :unresolved} = Repo.get!(Error, error.id)
  end

  test "an error resolved by a status change while its updated_at is ahead of the clock is still reopened by its next occurrence" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence([]))
    set_updated_at(error, DateTime.shift(DateTime.utc_now(), hour: 1))
    {:ok, 1} = Errors.set_status(conf, [error.id], :resolved)

    {:ok, recorded} = Errors.record(conf, occurrence([]))

    assert recorded.reopened
  end

  test "resolving an error that came back keeps the time it came back" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence([]))
    {:ok, 1} = Errors.set_status(conf, [error.id], :resolved)
    {:ok, _recorded} = Errors.record(conf, occurrence([]))
    %Error{regressed_at: regressed_at} = Repo.get!(Error, error.id)

    {:ok, 1} = Errors.set_status(conf, [error.id], :resolved)

    assert %Error{regressed_at: ^regressed_at} = Repo.get!(Error, error.id)
  end

  test "with a configured prefix the status is changed in that schema" do
    PrivatePrefix.migrate_up()
    conf = config(prefix: PrivatePrefix.name())
    {:ok, error} = Errors.record(conf, occurrence(kind: "Imison.PrefixError#{System.unique_integer([:positive])}"))

    assert Errors.set_status(conf, [error.id], :ignored) == {:ok, 1}

    assert %Error{status: :ignored} = Repo.get!(Error, error.id, prefix: PrivatePrefix.name())
  end

  test "with no PubSub running under the configured name, a status change is still stored and the failed broadcast is logged" do
    conf = config(pubsub: Imison.Test.MissingPubSub)
    {:ok, error} = Errors.record(conf, occurrence([]))

    {result, log} = with_log(fn -> Errors.set_status(conf, [error.id], :resolved) end)

    assert result == {:ok, 1}
    assert %Error{status: :resolved} = Repo.get!(Error, error.id)
    assert log =~ "Imison failed to broadcast a change to errors"
  end

  test "muting stores the given errors as muted and leaves the others as they were" do
    conf = config()
    {:ok, first} = Errors.record(conf, occurrence(kind: "KeyError"))
    {:ok, second} = Errors.record(conf, occurrence(kind: "ArgumentError"))
    {:ok, untouched} = Errors.record(conf, occurrence(kind: "MatchError"))

    assert Errors.set_muted(conf, [first.id, second.id], true) == {:ok, 2}

    assert %Error{muted: true} = Repo.get!(Error, first.id)
    assert %Error{muted: true} = Repo.get!(Error, second.id)
    assert %Error{muted: false} = Repo.get!(Error, untouched.id)
  end

  test "unmuting stores a muted error as unmuted" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence([]))
    {:ok, 1} = Errors.set_muted(conf, [error.id], true)

    assert Errors.set_muted(conf, [error.id], false) == {:ok, 1}

    assert %Error{muted: false} = Repo.get!(Error, error.id)
  end

  test "muting keeps the error's status" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence([]))
    {:ok, 1} = Errors.set_status(conf, [error.id], :resolved)

    {:ok, 1} = Errors.set_muted(conf, [error.id], true)

    assert %Error{status: :resolved, muted: true} = Repo.get!(Error, error.id)
  end

  test "ids given as text are muted like integer ids and anything that is not an error id is skipped" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence([]))

    assert Errors.set_muted(conf, [Integer.to_string(error.id), "abc", "9223372036854775808", -1, nil], true) == {:ok, 1}

    assert %Error{muted: true} = Repo.get!(Error, error.id)
  end

  test "an error muted and resolved while its updated_at is ahead of the clock is still reopened by its next occurrence" do
    conf = config()
    {:ok, error} = Errors.record(conf, occurrence([]))
    set_updated_at(error, DateTime.shift(DateTime.utc_now(), hour: 1))
    {:ok, 1} = Errors.set_status(conf, [error.id], :resolved)
    {:ok, 1} = Errors.set_muted(conf, [error.id], true)

    {:ok, recorded} = Errors.record(conf, occurrence([]))

    assert recorded.reopened
    assert recorded.muted
  end

  test "with a configured prefix the error is muted in that schema" do
    PrivatePrefix.migrate_up()
    conf = config(prefix: PrivatePrefix.name())
    {:ok, error} = Errors.record(conf, occurrence(kind: "Imison.PrefixError#{System.unique_integer([:positive])}"))

    assert Errors.set_muted(conf, [error.id], true) == {:ok, 1}

    assert %Error{muted: true} = Repo.get!(Error, error.id, prefix: PrivatePrefix.name())
  end

  test "pruning deletes occurrences older than the retention days, keeps the newer ones and returns how many rows went" do
    conf = config(retention_days: 7)
    now = ~U[2026-11-12 12:00:00.000000Z]
    {:ok, error} = Errors.record(conf, occurrence(occurred_at: DateTime.shift(now, day: -8)))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: DateTime.shift(now, day: -6)))

    assert Errors.prune(conf, now) == %{occurrences: 1, hourly_counts: 1}

    assert occurred_at_of_occurrences(error) == [DateTime.shift(now, day: -6)]
  end

  test "pruning keeps an error whose occurrences all went, with its count and first and last seen unchanged" do
    conf = config(retention_days: 7)
    now = ~U[2026-11-12 12:00:00.000000Z]
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: DateTime.shift(now, day: -10)))
    {:ok, error} = Errors.record(conf, occurrence(occurred_at: DateTime.shift(now, day: -9)))
    before_pruning = Repo.get!(Error, error.id)

    Errors.prune(conf, now)

    assert occurred_at_of_occurrences(error) == []

    assert %Error{occurrence_count: 2, first_seen_at: first_seen_at, last_seen_at: last_seen_at} =
             Repo.get!(Error, error.id)

    assert first_seen_at == before_pruning.first_seen_at
    assert last_seen_at == before_pruning.last_seen_at
  end

  test "pruning deletes hourly counts older than the retention days and keeps the newer ones" do
    conf = config(retention_days: 7)
    now = ~U[2026-11-12 12:00:00.000000Z]
    {:ok, error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-04 09:30:00.000000Z]))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: ~U[2026-11-06 15:30:00.000000Z]))

    Errors.prune(conf, now)

    assert hours_of_hourly_counts(error) == [~U[2026-11-06 15:00:00Z]]
  end

  test "pruning without a retention_days option keeps 30 days" do
    conf = config()
    now = ~U[2026-11-12 12:00:00.000000Z]
    {:ok, error} = Errors.record(conf, occurrence(occurred_at: DateTime.shift(now, day: -31)))
    {:ok, _error} = Errors.record(conf, occurrence(occurred_at: DateTime.shift(now, day: -29)))

    Errors.prune(conf, now)

    assert occurred_at_of_occurrences(error) == [DateTime.shift(now, day: -29)]
    assert hours_of_hourly_counts(error) == [~U[2026-10-14 12:00:00Z]]
  end

  test "with a configured prefix old occurrences and hourly counts are pruned in that schema" do
    PrivatePrefix.migrate_up()
    conf = config(prefix: PrivatePrefix.name(), retention_days: 7)
    now = ~U[2026-11-12 12:00:00.000000Z]
    kind = "Imison.PrefixError#{System.unique_integer([:positive])}"
    {:ok, _error} = Errors.record(conf, occurrence(kind: kind, occurred_at: DateTime.shift(now, day: -8)))
    {:ok, _error} = Errors.record(conf, occurrence(kind: kind, occurred_at: DateTime.shift(now, day: -6)))

    assert Errors.prune(conf, now) == %{occurrences: 1, hourly_counts: 1}

    assert [%Occurrence{}] = Repo.all(Occurrence, prefix: PrivatePrefix.name())
    assert [%HourlyCount{}] = Repo.all(HourlyCount, prefix: PrivatePrefix.name())
  end

  test "processes on their own connections pruning at once both finish and leave the same rows as one prune" do
    conf = config(retention_days: 7)
    now = DateTime.utc_now()
    kind = "Imison.PrunedError#{System.unique_integer([:positive])}"
    old_occurrences = 30
    pruners = 2

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Error |> from(as: :error) |> where([error: error], error.kind == ^kind) |> Repo.delete_all()
      end)
    end)

    error =
      Sandbox.unboxed_run(Repo, fn ->
        for days_ago <- 8..(7 + old_occurrences) do
          Errors.record(conf, occurrence(kind: kind, occurred_at: DateTime.shift(now, day: -days_ago)))
        end

        {:ok, error} = Errors.record(conf, occurrence(kind: kind, occurred_at: DateTime.shift(now, day: -1)))
        error
      end)

    results =
      1..pruners
      |> Task.async_stream(fn _pruner -> Sandbox.unboxed_run(Repo, fn -> Errors.prune(conf, now) end) end,
        max_concurrency: pruners
      )
      |> Enum.to_list()

    assert [{:ok, %{occurrences: _first}}, {:ok, %{occurrences: _second}}] = results

    assert Sandbox.unboxed_run(Repo, fn -> occurred_at_of_occurrences(error) end) == [DateTime.shift(now, day: -1)]
    assert Sandbox.unboxed_run(Repo, fn -> length(hours_of_hourly_counts(error)) end) == 1
  end

  defp occurred_at_of_occurrences(%Error{id: error_id}) do
    Occurrence
    |> from(as: :occurrence)
    |> where([occurrence: occurrence], occurrence.error_id == ^error_id)
    |> order_by([occurrence: occurrence], occurrence.occurred_at)
    |> select([occurrence: occurrence], occurrence.occurred_at)
    |> Repo.all()
  end

  defp occurrence_ids_oldest_first(%Error{id: error_id}) do
    Occurrence
    |> from(as: :occurrence)
    |> where([occurrence: occurrence], occurrence.error_id == ^error_id)
    |> order_by([occurrence: occurrence], asc: occurrence.occurred_at, asc: occurrence.id)
    |> select([occurrence: occurrence], occurrence.id)
    |> Repo.all()
  end

  defp hours_of_hourly_counts(%Error{id: error_id}) do
    HourlyCount
    |> from(as: :hourly_count)
    |> where([hourly_count: hourly_count], hourly_count.error_id == ^error_id)
    |> order_by([hourly_count: hourly_count], hourly_count.hour)
    |> select([hourly_count: hourly_count], hourly_count.hour)
    |> Repo.all()
  end

  defp set_updated_at(%Error{id: error_id}, updated_at) do
    Error
    |> from(as: :error)
    |> where([error: error], error.id == ^error_id)
    |> Repo.update_all(set: [updated_at: updated_at])
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
