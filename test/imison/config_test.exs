defmodule Imison.ConfigTest do
  use ExUnit.Case, async: true

  alias Imison.Config
  alias Imison.Test.Repo

  defmodule Channel do
    @moduledoc false
  end

  defmodule Mailer do
    @moduledoc false

    def deliver(_email, _config), do: {:ok, %{}}
  end

  test "options left out are filled in with their defaults" do
    config = Config.new(repo: Repo, username: "admin", password: "secret")

    assert %Config{
             name: Imison,
             repo: Repo,
             username: "admin",
             password: "secret",
             pubsub: nil,
             mailer: nil,
             from: nil,
             release: nil,
             retention_days: 30,
             channels: [],
             enabled: true,
             filter: ["password", "token", "secret", "authorization", "cookie"],
             ignore: [],
             prefix: "public"
           } = config
  end

  test "every documented option is accepted with a valid value" do
    config =
      Config.new(
        name: :errors,
        repo: Repo,
        username: "admin",
        password: "secret",
        pubsub: :host_pubsub,
        mailer: Mailer,
        from: "errors@example.com",
        release: "1.2.3",
        retention_days: 7,
        channels: [Channel],
        enabled: false,
        filter: ["api_key"],
        ignore: [ArgumentError],
        prefix: "private"
      )

    assert %Config{
             name: :errors,
             pubsub: :host_pubsub,
             mailer: Mailer,
             from: "errors@example.com",
             release: "1.2.3",
             retention_days: 7,
             channels: [Channel],
             enabled: false,
             filter: ["api_key"],
             ignore: [ArgumentError],
             prefix: "private"
           } = config
  end

  test "validate returns the error message instead of raising" do
    assert {:error, message} =
             Config.validate(repo: Repo, username: "admin", password: "secret", enabled: "yes")

    assert message =~ ":enabled"
  end

  test "a missing repo is refused naming :repo" do
    assert_raise ArgumentError, ~r/missing required option :repo/, fn ->
      Config.new(username: "admin", password: "secret")
    end
  end

  test "a missing username is refused naming :username" do
    assert_raise ArgumentError, ~r/missing required option :username/, fn ->
      Config.new(repo: Repo, password: "secret")
    end
  end

  test "a missing password is refused naming :password" do
    assert_raise ArgumentError, ~r/missing required option :password/, fn ->
      Config.new(repo: Repo, username: "admin")
    end
  end

  test "a repo module that doesn't export config/0 is refused naming :repo" do
    assert_raise ArgumentError, ~r/expected :repo to implement/, fn ->
      Config.new(repo: Enum, username: "admin", password: "secret")
    end
  end

  test "a repo module that isn't loaded is refused naming :repo" do
    assert_raise ArgumentError, ~r/expected :repo to be a loaded module/, fn ->
      Config.new(repo: Imison.Test.MissingRepo, username: "admin", password: "secret")
    end
  end

  test "a retention_days that isn't a positive integer is refused naming :retention_days" do
    assert_raise ArgumentError, ~r/expected :retention_days to be a positive integer, got: 0/, fn ->
      Config.new(repo: Repo, username: "admin", password: "secret", retention_days: 0)
    end
  end

  test "an enabled flag that isn't a boolean is refused naming :enabled" do
    assert_raise ArgumentError, ~r/expected :enabled to be a boolean, got: "yes"/, fn ->
      Config.new(repo: Repo, username: "admin", password: "secret", enabled: "yes")
    end
  end

  test "an unknown option is refused naming it and suggesting the closest known option" do
    assert_raise ArgumentError, ~r/unknown option :reop, did you mean :repo\?/, fn ->
      Config.new(reop: Repo, username: "admin", password: "secret")
    end
  end

  test "an option given twice is refused naming the duplicate" do
    assert_raise ArgumentError, ~r/found duplicate options: \[:retention_days\]/, fn ->
      Config.new(repo: Repo, username: "admin", password: "secret", retention_days: 7, retention_days: 9)
    end
  end

  test "a mailer module that doesn't export deliver/2 is refused naming :mailer" do
    assert_raise ArgumentError, ~r/expected :mailer to be one of/, fn ->
      Config.new(repo: Repo, username: "admin", password: "secret", mailer: Repo)
    end
  end

  test "an ignore entry that isn't an exception module is refused naming :ignore" do
    assert_raise ArgumentError, ~r/expected :ignore to be a list of/, fn ->
      Config.new(repo: Repo, username: "admin", password: "secret", ignore: [Enum])
    end
  end

  test "a from address that isn't a string is refused naming :from" do
    assert_raise ArgumentError, ~r/expected :from to be one of/, fn ->
      Config.new(repo: Repo, username: "admin", password: "secret", from: false)
    end
  end

  test "a prefix that isn't a string is refused naming :prefix" do
    assert_raise ArgumentError, ~r/expected :prefix to be a string, got: :private/, fn ->
      Config.new(repo: Repo, username: "admin", password: "secret", prefix: :private)
    end
  end
end
