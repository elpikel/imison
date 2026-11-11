import Config

alias Imison.Test.Repo

config :imison, Imison.Test.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "imison-test-endpoint-secret-key-base-used-only-by-the-test-suite-0123456789",
  live_view: [signing_salt: "imison-test-live-view"],
  pubsub_server: Imison.Test.PubSub,
  render_errors: [formats: [html: Imison.Test.ErrorHTML], layout: false],
  server: false

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

config :phoenix, :json_library, JSON
