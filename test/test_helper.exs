alias Imison.Test.Repo

{:ok, _repo} = Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
ExUnit.start()
