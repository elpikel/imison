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

  defp upsert_error(%Config{repo: repo, prefix: prefix}, %{occurred_at: occurred_at} = occurrence) do
    now = DateTime.utc_now()

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
      on_conflict: newest_occurrence_wins(now),
      conflict_target: :fingerprint,
      returning: true
    )
  end

  defp newest_occurrence_wins(now) do
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
        updated_at: ^now
      ]
    )
  end

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
