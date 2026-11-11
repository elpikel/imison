defmodule Imision.DataCase do
  @moduledoc """
  Test case for tests that touch the database.

  Each test checks out its own sandbox connection, so its writes are rolled
  back when it finishes. Use `async: true` unless the test shares the
  connection with processes it doesn't own.
  """
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Imision.Test.Repo
    end
  end

  setup tags do
    owner = Sandbox.start_owner!(Imision.Test.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    :ok
  end
end
