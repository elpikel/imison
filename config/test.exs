import Config

alias Imision.Test.Repo

config :imision, Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "imision_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  priv: "test/support/postgres"

config :imision, ecto_repos: [Repo]

config :logger, level: :warning
