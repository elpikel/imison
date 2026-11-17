defmodule Imison.PrunerTest do
  use Imison.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  import Imison.Test.CaptureHelpers

  alias Imison.Analytics.Pageview
  alias Imison.Analytics.Salt
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

  defmodule PageviewsUnavailableRepo do
    @moduledoc false

    alias Imison.Test.Repo

    def config, do: Repo.config()

    def delete_all(%Ecto.Query{from: %{source: {_table, Pageview}}}, _opts),
      do: raise(DBConnection.ConnectionError, "connection not available")

    def delete_all(queryable, opts), do: Repo.delete_all(queryable, opts)
  end

  defmodule OccurrencesUnavailableRepo do
    @moduledoc false

    alias Imison.Test.Repo

    def config, do: Repo.config()

    def delete_all(%Ecto.Query{from: %{source: {_table, Occurrence}}}, _opts),
      do: raise(DBConnection.ConnectionError, "connection not available")

    def delete_all(queryable, opts), do: Repo.delete_all(queryable, opts)
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

  test "the pruner deletes old pageviews and salts on its own each time the interval passes" do
    conf = config(analytics_retention_days: 30)
    today = Date.utc_today()
    store_pageview(%{path: "/old", days_ago: 31})
    store_pageview(%{path: "/recent", days_ago: 1})
    Salt.for_days(conf, [Date.add(today, -2), Date.add(today, -1), today])
    pruner = start_supervised!({Pruner, conf: conf, initial_delay: 0, interval: 10})

    wait_for_next_run(pruner)
    assert stored_paths() == ["/recent"]
    assert stored_salt_days() == [Date.add(today, -1), today]

    store_pageview(%{path: "/older", days_ago: 40})
    wait_for_next_run(pruner)
    assert stored_paths() == ["/recent"]
  end

  @tag :capture_log
  test "a failure while pruning pageviews still prunes old occurrences" do
    conf = config(retention_days: 7)
    {:ok, error} = Errors.record(conf, occurrence(days_ago: 8))
    {:ok, _error} = Errors.record(conf, occurrence(days_ago: 1))
    failing_conf = %{conf | repo: PageviewsUnavailableRepo}
    pruner = start_supervised!({Pruner, conf: failing_conf, initial_delay: 0, interval: 10})

    wait_for_next_run(pruner)

    assert [%Occurrence{}] = occurrences(error)
  end

  @tag :capture_log
  test "a failure while pruning occurrences still prunes old pageviews and salts" do
    conf = config(analytics_retention_days: 30)
    store_pageview(%{path: "/old", days_ago: 31})
    Salt.for_days(conf, [Date.add(Date.utc_today(), -2)])
    failing_conf = %{conf | repo: OccurrencesUnavailableRepo}
    pruner = start_supervised!({Pruner, conf: failing_conf, initial_delay: 0, interval: 10})

    wait_for_next_run(pruner)

    assert stored_paths() == []
    assert stored_salt_days() == []
  end

  test "a database failure while pruning pageviews is logged under the imison domain" do
    conf = config(repo: UnavailableRepo)
    pruner = start_supervised!({Pruner, conf: conf, initial_delay: 0, interval: 10})

    log = capture_log([metadata: [:domain]], fn -> wait_for_next_run(pruner) end)

    assert log =~ ~r/domain=elixir\.imison \[error\] Imison failed to prune old pageviews.*connection not available/s
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

  defp store_pageview(%{path: path, days_ago: days_ago}) do
    Repo.insert_all(Pageview, [
      %{
        visitor_id: System.unique_integer([:positive]),
        path: path,
        source: nil,
        occurred_at: DateTime.shift(DateTime.utc_now(), day: -days_ago)
      }
    ])
  end

  defp stored_paths do
    Pageview
    |> from(as: :pageview)
    |> order_by([pageview: pageview], asc: pageview.path)
    |> select([pageview: pageview], pageview.path)
    |> Repo.all()
  end

  defp stored_salt_days do
    Salt
    |> from(as: :salt)
    |> order_by([salt: salt], asc: salt.day)
    |> select([salt: salt], salt.day)
    |> Repo.all()
  end
end
