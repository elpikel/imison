defmodule Imison.Web.LoginThrottleTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Imison.Config
  alias Imison.Test.Repo
  alias Imison.Web.LoginThrottle

  @concurrent_attempts 10

  test "concurrent attempts after a wait has run out are settled one at a time, so only the first reaches the credential check" do
    config = Config.new(name: make_ref(), repo: Repo, username: "admin", password: "secret")
    test_process = self()
    on_exit(fn -> with_committing_connection(fn -> Repo.delete_all("imison_login_failures") end) end)

    with_committing_connection(fn -> insert_failures(5, seconds_ago: 10) end)
    now = DateTime.utc_now()

    check_credentials = fn ->
      send(test_process, :credentials_checked)
      false
    end

    outcomes =
      1..@concurrent_attempts
      |> Task.async_stream(
        fn _attempt -> with_committing_connection(fn -> LoginThrottle.attempt(config, now, check_credentials) end) end,
        max_concurrency: @concurrent_attempts,
        ordered: false
      )
      |> Enum.map(fn {:ok, outcome} -> outcome end)

    assert Enum.frequencies(outcomes) == %{:rejected => 1, {:wait, 2} => @concurrent_attempts - 1}
    assert_received :credentials_checked
    refute_received :credentials_checked
  end

  defp with_committing_connection(function) do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    try do
      function.()
    after
      Sandbox.checkin(Repo)
    end
  end

  defp insert_failures(count, seconds_ago: seconds_ago) do
    failed_at = DateTime.shift(DateTime.utc_now(), second: -seconds_ago)

    Repo.insert_all("imison_login_failures", List.duplicate(%{failed_at: failed_at}, count))
  end
end
