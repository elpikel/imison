defmodule Imison.BatchDelete do
  @moduledoc false

  import Ecto.Query

  alias Imison.Config

  @batch_size 10_000

  @type old_rows :: %{schema: module(), timestamp: atom(), cutoff: DateTime.t()}

  @spec delete_older_than(Config.t(), old_rows()) :: non_neg_integer()
  def delete_older_than(%Config{} = conf, %{schema: _schema, timestamp: _timestamp, cutoff: _cutoff} = old_rows) do
    delete_in_batches(conf, old_rows, 0)
  end

  defp delete_in_batches(%Config{repo: repo, prefix: prefix} = conf, old_rows, deleted_so_far) do
    %{schema: schema, timestamp: timestamp, cutoff: cutoff} = old_rows

    batch_ids =
      schema
      |> from(as: :old_row)
      |> where([old_row: old_row], field(old_row, ^timestamp) < ^cutoff)
      |> select([old_row: old_row], old_row.id)
      |> limit(@batch_size)
      |> lock("FOR UPDATE SKIP LOCKED")

    {deleted, _rows} =
      schema
      |> from(as: :old_row)
      |> where([old_row: old_row], old_row.id in subquery(batch_ids))
      |> repo.delete_all(prefix: prefix)

    if deleted < @batch_size,
      do: deleted_so_far + deleted,
      else: delete_in_batches(conf, old_rows, deleted_so_far + deleted)
  end
end
