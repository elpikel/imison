defmodule Imison.MixProject do
  use Mix.Project

  def project do
    [
      app: :imison,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      name: "Imison",
      docs: docs()
    ]
  end

  def cli do
    [preferred_envs: [check: :test]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :public_key, :crypto],
      mod: {Imison.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/dashboard.md",
        "guides/capturing-errors.md",
        "guides/notifications.md",
        "guides/custom-channels.md",
        "guides/configuration.md"
      ],
      groups_for_extras: [Guides: ~r"guides/"],
      # The guides show images/<file> and the README guides/images/<file>, the paths GitHub resolves.
      assets: %{"guides/images" => "images", "guides/images/" => "guides/images"},
      groups_for_modules: [
        Notifications: [~r"Imison.Notifications"],
        Dashboard: [~r"Imison.Web"]
      ]
    ]
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      check: [
        "compile --warnings-as-errors --force",
        "deps.unlock --check-unused",
        "format --check-formatted",
        "credo --strict",
        "test"
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 1.14", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ecto_sql, "~> 3.14"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:ex_slop, "~> 0.4.5", only: [:dev, :test], runtime: false},
      {:igniter, "~> 0.8", optional: true},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_view, "~> 1.1"},
      {:phx_new, "~> 1.8", only: :test, runtime: false},
      {:postgrex, "~> 0.22"},
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false},
      {:swoosh, "~> 1.29", optional: true},
      {:telemetry, "~> 1.3"}
    ]
  end
end
