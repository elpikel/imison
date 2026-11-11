defmodule Imision.MixProject do
  use Mix.Project

  def project do
    [
      app: :imision,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def cli do
    [preferred_envs: [check: :test]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp aliases do
    [
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4.5", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false}
    ]
  end
end
