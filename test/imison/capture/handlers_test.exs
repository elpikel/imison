defmodule Imison.Capture.HandlersTest do
  use Imison.DataCase, async: false

  alias Imison.Capture.LoggerHandler
  alias Imison.Capture.Telemetry

  test "a running instance's logger and telemetry handlers are detached when it stops" do
    name = make_ref()
    start_supervised!({Imison, name: name, repo: Repo, username: "admin", password: "secret"})

    assert %{logger: [_handler], telemetry: [_ | _]} = attached_handlers(name)

    stop_supervised!(name)

    assert attached_handlers(name) == %{logger: [], telemetry: []}
  end

  test "an instance starts when a predecessor under its name was killed and left its handlers attached" do
    name = make_ref()
    :ok = LoggerHandler.attach(name)
    :ok = Telemetry.attach(name)

    start_supervised!({Imison, name: name, repo: Repo, username: "admin", password: "secret"})

    assert %{logger: [_handler], telemetry: [_ | _]} = attached_handlers(name)
  end

  test "an instance with a name too long for an atom starts with its logger handler attached" do
    name = {:tenant, String.duplicate("a", 300)}

    start_supervised!({Imison, name: name, repo: Repo, username: "admin", password: "secret"})

    assert %{logger: [_handler]} = attached_handlers(name)
  end

  defp attached_handlers(name) do
    %{
      logger: for(%{id: id, config: %{name: ^name}} <- :logger.get_handler_config(), do: id),
      telemetry: for(%{id: id, config: %{name: ^name}} <- :telemetry.list_handlers([]), do: id)
    }
  end
end
