defmodule Pass.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :pass,
      version: @version,
      elixir: "~> 1.20-rc",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),
      releases: releases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Pass.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp releases do
    [
      pass: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            macos_aarch64: [os: :darwin, cpu: :aarch64],
            macos_x86_64: [os: :darwin, cpu: :x86_64],
            linux_x86_64: [os: :linux, cpu: :x86_64],
            linux_aarch64: [os: :linux, cpu: :aarch64]
          ]
        ],
        cookie: "pass_#{@version}"
      ]
    ]
  end

  defp deps do
    [
      # Jido ecosystem
      {:jido, "~> 2.0"},
      {:jido_action, "~> 2.0"},
      {:jido_signal, "~> 2.0"},
      {:jido_mcp, github: "agentjido/jido_mcp", branch: "main"},

      # Storage (SQLite — zero config, ships with binary)
      {:exqlite, "~> 0.23"},

      # Identity (Ed25519 keypairs)
      {:ed25519, "~> 1.4"},

      # CLI
      {:owl, "~> 0.13"},

      # Serialization
      {:jason, "~> 1.4"},
      {:msgpax, "~> 2.4"},

      # HTTP (for --http serve mode)
      {:bandit, "~> 1.6"},
      {:plug, "~> 1.16"},

      # Binary packaging
      {:burrito, "~> 1.0"},

      # Dev/Test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.0", only: :test}
    ]
  end

  defp aliases do
    [
      precommit: ["format", "compile --warnings-as-errors", "credo --strict", "test"]
    ]
  end
end
