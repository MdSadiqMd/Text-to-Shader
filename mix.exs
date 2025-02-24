defmodule TextToShader.MixProject do
  use Mix.Project

  def project do
    [
      app: :text_to_shader,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TextToShaderApi.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:plug_cowboy, "~> 2.0"},
      {:jason, "~> 1.2"},
      {:httpoison, "~> 1.8.0", override: true},
      {:ssl_verify_fun, "~> 1.1.6", override: true},
      {:cors_plug, "~> 2.0"}
    ]
  end
end
