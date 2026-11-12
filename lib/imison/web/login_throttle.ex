defmodule Imison.Web.LoginThrottle do
  @moduledoc false

  import Ecto.Query

  alias Imison.Capture.FailureLog
  alias Imison.Config

  @type outcome :: :accepted | :rejected | {:wait, pos_integer()} | :unavailable

  @failures_table "imison_login_failures"
  @free_failures 5
  @window_seconds 15 * 60
  @maximum_wait_seconds 5 * 60
  @microseconds_per_second 1_000_000

  @spec attempt(Config.t(), DateTime.t(), (-> boolean())) :: outcome()
  def attempt(%Config{repo: repo} = config, %DateTime{} = now, check_credentials)
      when is_function(check_credentials, 0) do
    {:ok, outcome} =
      repo.transact(fn ->
        lock_failures(config)
        {:ok, settle_attempt(config, now, check_credentials)}
      end)

    outcome
  catch
    kind, reason ->
      FailureLog.error("Imison failed to check failed sign-ins", %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})

      :unavailable
  end

  defp settle_attempt(config, now, check_credentials) do
    case config |> recent_failures(now) |> seconds_until_next_attempt(now) do
      0 -> settle_credentials(config, now, check_credentials.())
      wait_seconds -> {:wait, wait_seconds}
    end
  end

  defp settle_credentials(%Config{repo: repo, prefix: prefix}, _now, true) do
    repo.delete_all(failures(), prefix: prefix)
    :accepted
  end

  defp settle_credentials(%Config{repo: repo, prefix: prefix}, now, false) do
    repo.insert_all(@failures_table, [%{failed_at: now}], prefix: prefix)

    failures()
    |> where([login_failure: login_failure], login_failure.failed_at <= type(^window_start(now), :utc_datetime_usec))
    |> repo.delete_all(prefix: prefix)

    :rejected
  end

  defp lock_failures(%Config{repo: repo, prefix: prefix}),
    do: repo.query!("SELECT pg_advisory_xact_lock($1)", [:erlang.phash2({@failures_table, prefix})])

  defp recent_failures(%Config{repo: repo, prefix: prefix}, now) do
    failures()
    |> where([login_failure: login_failure], login_failure.failed_at > type(^window_start(now), :utc_datetime_usec))
    |> select([login_failure: login_failure], %{
      count: count(login_failure.id),
      latest_failed_at: type(max(login_failure.failed_at), :utc_datetime_usec)
    })
    |> repo.one(prefix: prefix)
  end

  defp failures, do: from(@failures_table, as: :login_failure)

  defp seconds_until_next_attempt(%{count: count}, _now) when count < @free_failures, do: 0

  defp seconds_until_next_attempt(%{count: count, latest_failed_at: latest_failed_at}, now) do
    wait_seconds = min(Integer.pow(2, count - @free_failures), @maximum_wait_seconds)

    microseconds_left =
      latest_failed_at
      |> DateTime.shift(second: wait_seconds)
      |> DateTime.diff(now, :microsecond)

    microseconds_left
    |> Kernel.+(@microseconds_per_second - 1)
    |> div(@microseconds_per_second)
    |> max(0)
    |> min(@maximum_wait_seconds)
  end

  defp window_start(now), do: DateTime.shift(now, second: -@window_seconds)
end
