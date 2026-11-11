defmodule Imison.Errors do
  @moduledoc false

  import Ecto.Query

  alias Imison.Config
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

  @listed_errors_limit 100
  @heat_strip_hours 24
  @largest_id 9_223_372_036_854_775_807

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
  def get(%Config{repo: repo, prefix: prefix}, id) when is_integer(id) and id in 1..@largest_id//1 do
    Error
    |> from(as: :error)
    |> where([error: error], error.id == ^id)
    |> repo.one(prefix: prefix)
  end

  def get(%Config{} = conf, id) when is_binary(id) do
    case Integer.parse(id) do
      {integer_id, ""} -> get(conf, integer_id)
      _not_an_id -> nil
    end
  end

  def get(%Config{}, _id), do: nil

  @spec latest_occurrence(Config.t(), integer()) :: Occurrence.t() | nil
  def latest_occurrence(%Config{repo: repo, prefix: prefix}, error_id) do
    Occurrence
    |> from(as: :occurrence)
    |> where([occurrence: occurrence], occurrence.error_id == ^error_id)
    |> order_by([occurrence: occurrence], desc: occurrence.occurred_at, desc: occurrence.id)
    |> limit(1)
    |> repo.one(prefix: prefix)
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
    frames = Frame.from_stacktrace(stacktrace)
    grouping = Fingerprint.from_frames(kind, frames, repo.config()[:otp_app])

    repo.transact(fn ->
      error = upsert_error(conf, Map.merge(occurrence, grouping))
      insert_occurrence(conf, error, Map.put(occurrence, :frames, frames))
      count_in_hour(conf, error, occurrence)
      {:ok, error}
    end)
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

    %{error | reopened: reopened_by_this_call?(error)}
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
          ),
        regressed_at:
          fragment(
            "CASE WHEN ? = ? THEN GREATEST(?, ? + interval '1 microsecond') ELSE ? END",
            error.status,
            type(^:resolved, error.status),
            type(^now, error.updated_at),
            error.updated_at,
            error.regressed_at
          ),
        updated_at:
          fragment(
            "GREATEST(?, ? + interval '1 microsecond')",
            type(^now, error.updated_at),
            error.updated_at
          )
      ]
    )
  end

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
      line: frame.line
    }
  end

  defp start_of_hour(datetime) do
    %{datetime | minute: 0, second: 0, microsecond: {0, 0}}
  end
end
