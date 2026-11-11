defmodule ImisonTest do
  use ExUnit.Case, async: false

  alias Imison.Config
  alias Imison.Test.Repo

  test "starts with a repo, username and password" do
    name = make_ref()

    assert {:ok, pid} = start_supervised({Imison, name: name, repo: Repo, username: "admin", password: "secret"})

    assert Process.alive?(pid)
  end

  test "returns the running config by name with defaults filled in" do
    name = make_ref()

    start_supervised!({Imison, name: name, repo: Repo, username: "admin", password: "secret"})

    assert %Config{name: ^name, repo: Repo, retention_days: 30, enabled: true} = Imison.config(name)
  end

  test "fails to start without a username, naming the option" do
    assert {:error, {{:EXIT, {%ArgumentError{message: message}, _stacktrace}}, _child_spec}} =
             start_supervised({Imison, name: make_ref(), repo: Repo, password: "secret"})

    assert message =~ ":username"
  end

  test "fails to start with an unknown option, naming it and suggesting the closest known one" do
    assert {:error, {{:EXIT, {%ArgumentError{message: message}, _stacktrace}}, _child_spec}} =
             start_supervised({Imison, name: make_ref(), reop: Repo, username: "admin", password: "secret"})

    assert message =~ "unknown option :reop, did you mean :repo?"
  end
end
