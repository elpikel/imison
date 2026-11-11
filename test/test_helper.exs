alias Imison.Test.Repo

{:ok, _repo} = Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)

{:ok, _web} =
  Supervisor.start_link([{Phoenix.PubSub, name: Imison.Test.PubSub}, Imison.Test.Endpoint], strategy: :one_for_one)

ExUnit.start()
