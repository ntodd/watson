defmodule Watson.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Code intelligence for Elixir/Phoenix projects. Builds a searchable call graph for LLM coding agents."

  def project do
    [
      app: :watson,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      description: @description,
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :mix, :tools],
      mod: {Watson.Application, []}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{},
      files: ~w(lib mix.exs README.md LICENSE .formatter.exs)
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      test: ["test --no-start"]
    ]
  end
end
