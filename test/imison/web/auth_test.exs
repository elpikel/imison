defmodule Imison.Web.AuthTest do
  use ExUnit.Case, async: true

  alias Imison.Config
  alias Imison.Test.Repo
  alias Imison.Web.Auth

  test "the configured username and password are accepted" do
    config = Config.new(repo: Repo, username: "admin", password: "s3cret")

    assert Auth.valid_credentials?(config, "admin", "s3cret")
  end

  test "a wrong username is refused" do
    config = Config.new(repo: Repo, username: "admin", password: "s3cret")

    refute Auth.valid_credentials?(config, "root", "s3cret")
  end

  test "a wrong password is refused" do
    config = Config.new(repo: Repo, username: "admin", password: "s3cret")

    refute Auth.valid_credentials?(config, "admin", "wrong")
  end

  test "empty username and password are refused" do
    config = Config.new(repo: Repo, username: "admin", password: "s3cret")

    refute Auth.valid_credentials?(config, "", "")
  end

  test "missing username and password are refused" do
    config = Config.new(repo: Repo, username: "admin", password: "s3cret")

    refute Auth.valid_credentials?(config, nil, nil)
  end
end
