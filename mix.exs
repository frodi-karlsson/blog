defmodule Webserver.MixProject do
  use Mix.Project

  def project do
    [
      app: :webserver,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      dialyzer: [
        plt_add_apps: [:mix]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Webserver, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [server: ["assets.build", "run --no-halt"]]
  end

  defp deps do
    [
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:plug, "~> 1.0"},
      {:telemetry, "~> 1.0"},
      {:dart_sass, "~> 0.7"},
      {:fs, "~> 8.6"},
      {:dialyxir, "~> 1.0", runtime: false},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end
end
