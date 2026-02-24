defmodule Webserver.MixProject do
  use Mix.Project

  def project do
    [
      app: :webserver,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [
        files: ["lib"],
        plt_add_apps: [:mix]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Webserver, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:plug, "~> 1.0"},
      {:telemetry, "~> 1.0"},
      {:dialyxir, "~> 1.0", runtime: false},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false}
    ]
  end
end
