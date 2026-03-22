defmodule ExRatatui.MixProject do
  use Mix.Project

  @description "Elixir bindings for the Rust ratatui terminal UI library"
  @source_url "https://github.com/mcass19/ex_ratatui"
  @changelog_url @source_url <> "/blob/main/CHANGELOG.md"
  @version "0.4.2"

  def project do
    [
      app: :ex_ratatui,
      description: @description,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      package: package(),
      name: "ExRatatui",
      homepage_url: @source_url,
      source_url: @source_url,
      docs: docs(),
      dialyzer: [
        plt_local_path: "plts",
        plt_core_path: "plts/core",
        plt_add_apps: [:rustler]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp aliases do
    [
      "rust.check": [
        "cmd --cd native/ex_ratatui cargo fmt --check",
        "cmd --cd native/ex_ratatui cargo clippy -- -D warnings",
        "cmd --cd native/ex_ratatui cargo test"
      ]
    ]
  end

  defp deps do
    [
      {:rustler_precompiled, "~> 0.8"},

      # Optional
      {:rustler, ">= 0.0.0", optional: true},

      # Dev
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @changelog_url
      },
      files: ~w(
        lib native .formatter.exs mix.exs README.md LICENSE CHANGELOG.md
        checksum-Elixir.ExRatatui.Native.exs
      ),
      exclude_patterns: ~w(native/ex_ratatui/target)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md": [title: "Overview"],
        "CONTRIBUTING.md": [title: "Contributing"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      groups_for_modules: [
        Application: [
          ExRatatui.App
        ],
        Layout: [
          ExRatatui.Frame,
          ExRatatui.Layout,
          ExRatatui.Layout.Rect
        ],
        Widgets: [
          ExRatatui.Widgets.Paragraph,
          ExRatatui.Widgets.Block,
          ExRatatui.Widgets.List,
          ExRatatui.Widgets.Table,
          ExRatatui.Widgets.Gauge,
          ExRatatui.Widgets.LineGauge,
          ExRatatui.Widgets.Tabs,
          ExRatatui.Widgets.Scrollbar,
          ExRatatui.Widgets.Clear
        ],
        Events: [
          ExRatatui.Event,
          ExRatatui.Event.Key,
          ExRatatui.Event.Mouse,
          ExRatatui.Event.Resize
        ],
        Style: [
          ExRatatui.Style
        ]
      ]
    ]
  end
end
