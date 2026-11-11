import Config

alias Imison.Test.Repo

config :imison, Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "imison_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  priv: "test/support/postgres"

config :imison, ecto_repos: [Repo]

config :logger, level: :warning
