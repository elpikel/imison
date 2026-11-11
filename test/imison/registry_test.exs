defmodule Imison.RegistryTest do
  use ExUnit.Case, async: false

  alias Imison.Test.Repo

  test "the config of a stopped instance is unavailable even before the registry cleans up its entry" do
    name = make_ref()
    start_supervised!({Imison, name: name, repo: Repo, username: "admin", password: "secret", enabled: false})
    partitions = registry_partitions()
    Enum.each(partitions, &:sys.suspend/1)

    try do
      stop_supervised!(name)

      assert_raise RuntimeError, ~r/No Imison instance named/, fn -> Imison.config(name) end
    after
      Enum.each(partitions, &:sys.resume/1)
    end
  end

  defp registry_partitions do
    for {_id, pid, _type, _modules} <- Supervisor.which_children(Imison.Registry), do: pid
  end
end
