defmodule Imison.PrunerTest do
  use Imison.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  import Imison.Test.CaptureHelpers

  alias Imison.Config
  alias Imison.Errors
  alias Imison.Errors.Error
  alias Imison.Errors.Occurrence
  alias Imison.Pruner

  defmodule UnavailableRepo do
    @moduledoc false

    def config, do: []

    def delete_all(_queryable, _opts), do: raise(DBConnection.ConnectionError, "connection not available")
  end

  test "a running instance starts a pruner" do
    name = start_imison()

    assert {_pid, _value} = Imison.Registry.lookup(name, Pruner)
  end

  test "an instance started with enabled: false starts no pruner" do
    name = start_imison(enabled: false)

    assert Imison.Registry.lookup(name, Pruner) == nil
  end

  test "the pruner deletes old occurrences on its own each time the interval passes" do
    conf = config(retention_days: 7)
    {:ok, error} = Errors.record(conf, occurrence(days_ago: 8))
    {:ok, _error} = Errors.record(conf, occurrence(days_ago: 1))
    pruner = start_supervised!({Pruner, conf: conf, initial_delay: 0, interval: 10})

    wait_for_next_run(pruner)
    assert [%Occurrence{}] = occurrences(error)

    {:ok, _error} = Errors.record(conf, occurrence(days_ago: 9))
    wait_for_next_run(pruner)
    assert [%Occurrence{}] = occurrences(error)
  end

  test "a database failure while pruning is logged under the imison domain and the pruner runs again" do
    conf = config(repo: UnavailableRepo)
    pruner = start_supervised!({Pruner, conf: conf, initial_delay: 0, interval: 10})

    log =
      capture_log([metadata: [:domain]], fn ->
        wait_for_next_run(pruner)
        wait_for_next_run(pruner)
      end)

    assert log =~ ~r/domain=elixir\.imison \[error\] Imison failed to prune old occurrences.*connection not available/s
    assert Process.alive?(pruner)
  end

  defp wait_for_next_run(pruner) do
    :erlang.trace(pruner, true, [:receive])

    receive do
      {:trace, ^pruner, :receive, :prune} -> :ok
    end

    :erlang.trace(pruner, false, [:receive])
    :sys.get_state(pruner)
  end

  defp config(opts) do
    [name: make_ref(), repo: Imison.Test.Repo, username: "admin", password: "secret"]
    |> Keyword.merge(opts)
    |> Config.new()
  end

  defp occurrences(%Error{id: error_id}) do
    Occurrence
    |> from(as: :occurrence)
    |> where([occurrence: occurrence], occurrence.error_id == ^error_id)
    |> Repo.all()
  end

  defp occurrence(days_ago: days_ago) do
    %{
      kind: "RuntimeError",
      message: "boom",
      stacktrace: [],
      context: %{},
      occurred_at: DateTime.shift(DateTime.utc_now(), day: -days_ago)
    }
  end
end
