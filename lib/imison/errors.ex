defmodule Imison.Errors do
  @moduledoc false

  import Ecto.Query

  alias Imison.Capture.FailureLog
  alias Imison.Config
  alias Imison.Errors.Broadcast
  alias Imison.Errors.Error
  alias Imison.Errors.Fingerprint
  alias Imison.Errors.Frame
  alias Imison.Errors.HourlyCount
  alias Imison.Errors.Occurrence

  @type occurrence :: %{
          required(:kind) => String.t(),
          required(:message) => String.t(),
          required(:stacktrace) => Exception.stacktrace(),
          required(:occurred_at) => DateTime.t(),
          optional(:context) => map(),
          optional(:release) => String.t() | nil
        }

  @type stepped_occurrence :: %{
          occurrence: Occurrence.t(),
          position: pos_integer(),
          total: pos_integer(),
          older_id: integer() | nil,
          newer_id: integer() | nil
        }

  @type summary_line :: %{
          error_id: pos_integer(),
          kind: String.t(),
          message: String.t(),
          location: String.t() | nil,
          count: non_neg_integer()
        }

  @type summary_section :: %{lines: [summary_line()], total: non_neg_integer()}

  @type daily_summary :: %{
          date: Date.t(),
          new: summary_section(),
          came_back: summary_section(),
          most_frequent: summary_section()
        }

  @listed_errors_limit 100
  @summary_section_limit 20
  @most_frequent_limit 5
  @heat_strip_hours 24
  @largest_id 9_223_372_036_854_775_807
  @change_broadcast_failure "Imison failed to broadcast a change to errors"
  @prune_batch_size 10_000
  @nearest_first %{older: :desc, newer: :asc}

  @spec list(Config.t(), status: atom(), search: String.t()) :: [Error.t()]
  def list(%Config{repo: repo, prefix: prefix}, opts) do
    status = Keyword.fetch!(opts, :status)

    Error
    |> from(as: :error)
    |> where([error: error], error.status == ^status)
    |> matching(Keyword.get(opts, :search, ""))
    |> order_by([error: error], desc: error.last_seen_at, desc: error.id)
    |> limit(@listed_errors_limit)
    |> repo.all(prefix: prefix)
  end

  @spec get(Config.t(), integer() | String.t()) :: Error.t() | nil
  def get(%Config{repo: repo, prefix: prefix}, id) do
    case database_id(id) do
      nil ->
        nil

      error_id ->
        Error
        |> from(as: :error)
        |> where([error: error], error.id == ^error_id)
        |> repo.one(prefix: prefix)
    end
  end

  @spec occurrence(Config.t(), integer(), integer() | String.t() | nil) :: stepped_occurrence() | nil
  def occurrence(%Config{} = conf, error_id, occurrence_id) do
    case selected_occurrence(conf, error_id, database_id(occurrence_id)) do
      nil ->
        nil

      %Occurrence{} = occurrence ->
        conf
        |> position_among_occurrences(occurrence)
        |> Map.merge(%{
          occurrence: occurrence,
          older_id: neighbour_id(conf, occurrence, :older),
          newer_id: neighbour_id(conf, occurrence, :newer)
        })
    end
  end

  @spec count_by_status(Config.t(), search: String.t()) :: %{atom() => non_neg_integer()}
  def count_by_status(%Config{repo: repo, prefix: prefix}, opts) do
    counts =
      Error
      |> from(as: :error)
      |> matching(Keyword.get(opts, :search, ""))
      |> group_by([error: error], error.status)
      |> select([error: error], %{status: error.status, count: count(error.id)})
      |> repo.all(prefix: prefix)
      |> Map.new(&{&1.status, &1.count})

    Map.new(Error.statuses(), &{&1, Map.get(counts, &1, 0)})
  end

  @spec hourly_counts(Config.t(), [integer()], DateTime.t()) :: %{integer() => [non_neg_integer()]}
  def hourly_counts(%Config{repo: repo, prefix: prefix}, error_ids, now) do
    current_hour = start_of_hour(now)
    first_hour = DateTime.shift(current_hour, hour: 1 - @heat_strip_hours)

    counts_by_error =
      HourlyCount
      |> from(as: :hourly_count)
      |> where([hourly_count: hourly_count], hourly_count.error_id in ^error_ids)
      |> where([hourly_count: hourly_count], hourly_count.hour >= ^first_hour and hourly_count.hour <= ^current_hour)
      |> select([hourly_count: hourly_count], %{
        error_id: hourly_count.error_id,
        hour: hourly_count.hour,
        count: hourly_count.count
      })
      |> repo.all(prefix: prefix)
      |> Enum.group_by(& &1.error_id)

    Map.new(error_ids, fn error_id ->
      counts =
        counts_by_error
        |> Map.get(error_id, [])
        |> counts_oldest_first(first_hour)

      {error_id, counts}
    end)
  end

  @spec record(Config.t(), occurrence()) :: {:ok, Error.t()}
  def record(%Config{repo: repo} = conf, %{kind: kind, stacktrace: stacktrace} = occurrence) do
    frames = Frame.from_stacktrace(stacktrace, repo.config()[:otp_app])
    grouping = Fingerprint.from_frames(kind, frames)

    repo.transact(fn ->
      error = upsert_error(conf, Map.merge(occurrence, grouping))
      insert_occurrence(conf, error, Map.put(occurrence, :frames, frames))
      count_in_hour(conf, error, occurrence)
      {:ok, error}
    end)
  end

  @spec set_status(Config.t(), [integer() | String.t()], atom() | String.t()) ::
          {:ok, non_neg_integer()} | {:error, :invalid_status}
  def set_status(%Config{} = conf, ids, status) do
    case known_status(status) do
      nil -> {:error, :invalid_status}
      known_status -> {:ok, update_errors(conf, ids, status: known_status)}
    end
  end

  @spec set_muted(Config.t(), [integer() | String.t()], boolean()) :: {:ok, non_neg_integer()}
  def set_muted(%Config{} = conf, ids, muted) when is_boolean(muted), do: {:ok, update_errors(conf, ids, muted: muted)}

  @spec prune(Config.t(), DateTime.t()) :: %{occurrences: non_neg_integer(), hourly_counts: non_neg_integer()}
  def prune(%Config{retention_days: retention_days} = conf, now) do
    cutoff = DateTime.shift(now, day: -retention_days)

    %{
      occurrences: delete_in_batches(conf, %{schema: Occurrence, timestamp: :occurred_at, cutoff: cutoff}, 0),
      hourly_counts: delete_in_batches(conf, %{schema: HourlyCount, timestamp: :hour, cutoff: cutoff}, 0)
    }
  end

  @spec daily_summary(Config.t(), Date.t()) :: daily_summary()
  def daily_summary(%Config{} = conf, %Date{} = date) do
    day = %{start: start_of_utc_day(date), end: date |> Date.add(1) |> start_of_utc_day()}

    %{
      date: date,
      new:
        day
        |> errors_with_day_count(:left)
        |> where([error: error], error.first_seen_at >= ^day.start and error.first_seen_at < ^day.end)
        |> summary_section(conf, %{
          order: [asc: dynamic([error: error], error.first_seen_at), asc: dynamic([error: error], error.id)],
          limit: @summary_section_limit
        }),
      came_back:
        day
        |> errors_with_day_count(:left)
        |> where([error: error], error.regressed_at >= ^day.start and error.regressed_at < ^day.end)
        |> summary_section(conf, %{
          order: [asc: dynamic([error: error], error.regressed_at), asc: dynamic([error: error], error.id)],
          limit: @summary_section_limit
        }),
      most_frequent:
        day
        |> errors_with_day_count(:inner)
        |> summary_section(conf, %{
          order: [desc: dynamic([day_count: day_count], day_count.count), asc: dynamic([error: error], error.id)],
          limit: @most_frequent_limit
        })
    }
  end

  @spec start_of_utc_day(Date.t()) :: DateTime.t()
  def start_of_utc_day(%Date{} = date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  defp database_id(id) when is_integer(id) and id in 1..@largest_id//1, do: id

  defp database_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer_id, ""} -> database_id(integer_id)
      _not_an_id -> nil
    end
  end

  defp database_id(_id), do: nil

  defp selected_occurrence(conf, error_id, nil), do: latest_occurrence(conf, error_id)

  defp selected_occurrence(%Config{repo: repo, prefix: prefix} = conf, error_id, occurrence_id) do
    requested_occurrence =
      error_id
      |> occurrences_of_error()
      |> where([occurrence: occurrence], occurrence.id == ^occurrence_id)
      |> repo.one(prefix: prefix)

    requested_occurrence || latest_occurrence(conf, error_id)
  end

  defp latest_occurrence(%Config{repo: repo, prefix: prefix}, error_id) do
    error_id
    |> occurrences_of_error()
    |> order_by([occurrence: occurrence], desc: occurrence.occurred_at, desc: occurrence.id)
    |> limit(1)
    |> repo.one(prefix: prefix)
  end

  defp position_among_occurrences(%Config{repo: repo, prefix: prefix}, %Occurrence{} = occurrence) do
    %Occurrence{error_id: error_id, occurred_at: occurred_at, id: id} = occurrence

    error_id
    |> occurrences_of_error()
    |> select([occurrence: occurrence], %{
      total: count(occurrence.id),
      position:
        filter(
          count(occurrence.id),
          occurrence.occurred_at < ^occurred_at or (occurrence.occurred_at == ^occurred_at and occurrence.id <= ^id)
        )
    })
    |> repo.one(prefix: prefix)
  end

  defp neighbour_id(%Config{repo: repo, prefix: prefix}, %Occurrence{error_id: error_id} = occurrence, direction) do
    error_id
    |> occurrences_of_error()
    |> where(^neighbour_side(occurrence, direction))
    |> order_by([occurrence: occurrence], [
      {^Map.fetch!(@nearest_first, direction), occurrence.occurred_at},
      {^Map.fetch!(@nearest_first, direction), occurrence.id}
    ])
    |> limit(1)
    |> select([occurrence: occurrence], occurrence.id)
    |> repo.one(prefix: prefix)
  end

  defp neighbour_side(%Occurrence{occurred_at: occurred_at, id: id}, :older) do
    dynamic(
      [occurrence: occurrence],
      occurrence.occurred_at < ^occurred_at or (occurrence.occurred_at == ^occurred_at and occurrence.id < ^id)
    )
  end

  defp neighbour_side(%Occurrence{occurred_at: occurred_at, id: id}, :newer) do
    dynamic(
      [occurrence: occurrence],
      occurrence.occurred_at > ^occurred_at or (occurrence.occurred_at == ^occurred_at and occurrence.id > ^id)
    )
  end

  defp occurrences_of_error(error_id) do
    Occurrence
    |> from(as: :occurrence)
    |> where([occurrence: occurrence], occurrence.error_id == ^error_id)
  end

  defp known_status(status) when is_atom(status), do: Enum.find(Error.statuses(), &(&1 == status))
  defp known_status(status) when is_binary(status), do: Enum.find(Error.statuses(), &(Atom.to_string(&1) == status))
  defp known_status(_status), do: nil

  defp update_errors(%Config{repo: repo, prefix: prefix} = conf, ids, changes) do
    error_ids = ids |> Enum.map(&database_id/1) |> Enum.reject(&is_nil/1)

    {count, changed_ids} =
      Error
      |> from(as: :error)
      |> where([error: error], error.id in ^error_ids)
      |> update(^[set: [{:updated_at, updated_at_moved_forward(DateTime.utc_now())} | changes]])
      |> select([error: error], error.id)
      |> repo.update_all([], prefix: prefix)

    if changed_ids != [], do: broadcast_changed(conf, changed_ids)
    count
  end

  defp broadcast_changed(conf, error_ids) do
    with {:error, reason} <- Broadcast.changed(conf, error_ids) do
      FailureLog.error(@change_broadcast_failure, %{kind: :error, reason: reason, stacktrace: []})
    end
  catch
    kind, reason ->
      FailureLog.error(@change_broadcast_failure, %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
  end

  defp delete_in_batches(%Config{repo: repo, prefix: prefix} = conf, old_rows, deleted_so_far) do
    %{schema: schema, timestamp: timestamp, cutoff: cutoff} = old_rows

    batch_ids =
      schema
      |> from(as: :old_row)
      |> where([old_row: old_row], field(old_row, ^timestamp) < ^cutoff)
      |> select([old_row: old_row], old_row.id)
      |> limit(@prune_batch_size)
      |> lock("FOR UPDATE SKIP LOCKED")

    {deleted, _rows} =
      schema
      |> from(as: :old_row)
      |> where([old_row: old_row], old_row.id in subquery(batch_ids))
      |> repo.delete_all(prefix: prefix)

    if deleted < @prune_batch_size,
      do: deleted_so_far + deleted,
      else: delete_in_batches(conf, old_rows, deleted_so_far + deleted)
  end

  defp counts_oldest_first(hourly_counts, first_hour) do
    counts_by_hours_since_first = Map.new(hourly_counts, &{DateTime.diff(&1.hour, first_hour, :hour), &1.count})
    Enum.map(0..(@heat_strip_hours - 1), &Map.get(counts_by_hours_since_first, &1, 0))
  end

  defp matching(query, search) do
    case String.trim(search) do
      "" -> query
      text -> where(query, [error: error], ^containing(text))
    end
  end

  defp containing(text) do
    pattern = "%" <> escape_like_wildcards(text) <> "%"

    dynamic(
      [error: error],
      ilike(error.kind, ^pattern) or ilike(error.message, ^pattern) or ilike(error.location, ^pattern)
    )
  end

  defp escape_like_wildcards(text), do: String.replace(text, ~r/[\\%_]/, "\\\\\\0")

  defp upsert_error(%Config{repo: repo, prefix: prefix}, %{occurred_at: occurred_at} = occurrence) do
    now = DateTime.utc_now()

    error =
      repo.insert!(
        %Error{
          fingerprint: occurrence.fingerprint,
          kind: occurrence.kind,
          message: occurrence.message,
          location: occurrence.location,
          first_seen_at: occurred_at,
          last_seen_at: occurred_at,
          occurrence_count: 1,
          inserted_at: now,
          updated_at: now
        },
        prefix: prefix,
        on_conflict: newest_occurrence_wins_and_resolved_regresses(now),
        conflict_target: :fingerprint,
        returning: true
      )

    %{error | created: created_by_this_call?(error), reopened: reopened_by_this_call?(error)}
  end

  defp newest_occurrence_wins_and_resolved_regresses(now) do
    Error
    |> from(as: :error)
    |> update([error: error],
      inc: [occurrence_count: 1],
      set: [
        message:
          fragment(
            "CASE WHEN EXCLUDED.last_seen_at >= ? THEN EXCLUDED.message ELSE ? END",
            error.last_seen_at,
            error.message
          ),
        last_seen_at: fragment("GREATEST(?, EXCLUDED.last_seen_at)", error.last_seen_at),
        status:
          fragment(
            "CASE WHEN ? = ? THEN ? ELSE ? END",
            error.status,
            type(^:resolved, error.status),
            type(^:unresolved, error.status),
            error.status
          )
      ]
    )
    |> update(^[set: [regressed_at: regressed_at_when_resolved(now), updated_at: updated_at_moved_forward(now)]])
  end

  defp regressed_at_when_resolved(now) do
    dynamic(
      [error: error],
      fragment(
        "CASE WHEN ? = ? THEN ? ELSE ? END",
        error.status,
        type(^:resolved, error.status),
        ^updated_at_moved_forward(now),
        error.regressed_at
      )
    )
  end

  defp updated_at_moved_forward(now) do
    dynamic(
      [error: error],
      fragment("GREATEST(?, ? + interval '1 microsecond')", type(^now, error.updated_at), error.updated_at)
    )
  end

  defp created_by_this_call?(%Error{inserted_at: inserted_at, updated_at: updated_at}),
    do: DateTime.compare(inserted_at, updated_at) == :eq

  defp reopened_by_this_call?(%Error{regressed_at: nil}), do: false

  defp reopened_by_this_call?(%Error{regressed_at: regressed_at, updated_at: updated_at}),
    do: DateTime.compare(regressed_at, updated_at) == :eq

  defp insert_occurrence(%Config{repo: repo, prefix: prefix}, %Error{id: error_id}, occurrence) do
    repo.insert!(
      %Occurrence{
        error_id: error_id,
        stacktrace: Enum.map(occurrence.frames, &stored_frame/1),
        context: Map.get(occurrence, :context, %{}),
        release: Map.get(occurrence, :release),
        occurred_at: occurrence.occurred_at
      },
      prefix: prefix
    )
  end

  defp count_in_hour(%Config{repo: repo, prefix: prefix}, %Error{id: error_id}, %{occurred_at: occurred_at}) do
    repo.insert!(
      %HourlyCount{error_id: error_id, hour: start_of_hour(occurred_at), count: 1},
      prefix: prefix,
      on_conflict: [inc: [count: 1]],
      conflict_target: [:error_id, :hour]
    )
  end

  defp stored_frame(%Frame{} = frame) do
    %{
      module: inspect(frame.module),
      function: Atom.to_string(frame.function),
      arity: frame.arity,
      file: frame.file,
      line: frame.line,
      application: frame.application?
    }
  end

  defp errors_with_day_count(day, join_kind) do
    Error
    |> from(as: :error)
    |> join(join_kind, [error: error], day_count in subquery(counts_in_day(day)),
      on: day_count.error_id == error.id,
      as: :day_count
    )
  end

  defp summary_section(errors, %Config{repo: repo, prefix: prefix}, %{order: order, limit: limit}) do
    %{
      lines:
        errors
        |> order_by(^order)
        |> limit(^limit)
        |> select([error: error, day_count: day_count], %{
          error_id: error.id,
          kind: error.kind,
          message: error.message,
          location: error.location,
          count: coalesce(day_count.count, 0)
        })
        |> repo.all(prefix: prefix),
      total: errors |> select([error: error], count(error.id)) |> repo.one(prefix: prefix)
    }
  end

  defp counts_in_day(%{start: day_start, end: day_end}) do
    HourlyCount
    |> from(as: :hourly_count)
    |> where([hourly_count: hourly_count], hourly_count.hour >= ^day_start and hourly_count.hour < ^day_end)
    |> group_by([hourly_count: hourly_count], hourly_count.error_id)
    |> select([hourly_count: hourly_count], %{
      error_id: hourly_count.error_id,
      count: type(sum(hourly_count.count), :integer)
    })
  end

  defp start_of_hour(datetime) do
    %{datetime | minute: 0, second: 0, microsecond: {0, 0}}
  end
end
