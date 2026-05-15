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
         steps: [:assemble, &swap_local_nif/1, &Burrito.wrap/1],
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

  # Replaces the precompiled musl NIF in the assembled release with a
  # locally cross-built one from `native/ex_ratatui/target/.../release/`.
  # Needed until the upstream `.cargo/config.toml` change ships in a new
  # ex_ratatui release; without this, the published musl NIF links
  # `libgcc_s.so.1` and fails to load under Burrito's musl payload.
  defp swap_local_nif(release) do
    repo_root = Path.expand("../..", __DIR__)

    source =
      Path.join([
        repo_root,
        "native/ex_ratatui/target/x86_64-unknown-linux-musl/release/libex_ratatui.so"
      ])

    if File.exists?(source) do
      [dest] =
        Path.wildcard(
          Path.join([
            release.path,
            "lib/ex_ratatui-*/priv/native/libex_ratatui-*-x86_64-unknown-linux-musl.so"
          ])
        )

      File.cp!(source, dest)

      Mix.shell().info(
        "[burrito_demo] swapped musl NIF -> #{Path.relative_to(dest, release.path)}"
      )
    end

    release
  end
end
