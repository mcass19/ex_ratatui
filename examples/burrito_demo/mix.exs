defmodule BurritoDemo.MixProject do
  use Mix.Project

  @app :burrito_demo
  @version "0.1.0"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BurritoDemo.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_ratatui, path: "../.."},
      {:rustler, ">= 0.0.0", optional: true},
      {:burrito, "~> 1.5"}
    ]
  end

  defp releases do
    [
      {@app,
       [
         steps: [:assemble, &Burrito.wrap/1],
         burrito: [
           targets: [
             linux: [os: :linux, cpu: :x86_64],
             macos: [os: :darwin, cpu: :x86_64],
             macos_silicon: [os: :darwin, cpu: :aarch64],
             windows: [os: :windows, cpu: :x86_64]
           ]
         ]
       ]}
    ]
  end
end
