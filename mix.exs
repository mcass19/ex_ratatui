defmodule ExRatatui.MixProject do
  use Mix.Project

  @description "Elixir bindings for the Rust ratatui terminal UI library"
  @source_url "https://github.com/mcass19/ex_ratatui"
  @changelog_url @source_url <> "/blob/main/CHANGELOG.md"
  @version "0.6.2"

  def project do
    [
      app: :ex_ratatui,
      description: @description,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      package: package(),
      name: "ExRatatui",
      homepage_url: @source_url,
      source_url: @source_url,
      docs: docs(),
      test_coverage: [
        summary: [threshold: 100],
        ignore_modules: [
          # Rust NIF bridge — no meaningful Elixir to cover
          ExRatatui.Native,
          # attach/3 blocks the caller and requires Erlang distribution;
          # exercise with: elixir --sname test -S mix test --include distributed
          ExRatatui.Distributed,
          # test-only modules loaded on :peer nodes for integration tests
          ExRatatui.Test.PeerApp,
          ExRatatui.Test.PeerHelper
        ]
      ],
      dialyzer: [
        plt_local_path: "plts",
        plt_core_path: "plts/core",
        plt_add_apps: [:rustler]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssh]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
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
        "guides/ssh_transport.md": [title: "Running TUIs over SSH"],
        "guides/distributed_transport.md": [title: "Running TUIs over Erlang Distribution"],
        "CONTRIBUTING.md": [title: "Contributing"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      skip_code_autolink_to: &skip_docs_autolink?/1,
      groups_for_extras: [
        Guides: Path.wildcard("guides/*.md")
      ],
      groups_for_modules: [
        Application: [
          ExRatatui.App
        ],
        "Reducer Runtime": [
          ExRatatui.Command,
          ExRatatui.Subscription,
          ExRatatui.Runtime
        ],
        "SSH Transport": [
          ExRatatui.Session,
          ExRatatui.SSH,
          ExRatatui.SSH.Daemon
        ],
        "Distribution Transport": [
          ExRatatui.Distributed,
          ExRatatui.Distributed.Listener
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
          ExRatatui.Widgets.Checkbox,
          ExRatatui.Widgets.TextInput,
          ExRatatui.Widgets.Clear,
          ExRatatui.Widgets.Markdown,
          ExRatatui.Widgets.Textarea,
          ExRatatui.Widgets.Throbber,
          ExRatatui.Widgets.Popup,
          ExRatatui.Widgets.WidgetList,
          ExRatatui.Widgets.SlashCommands,
          ExRatatui.Widgets.SlashCommands.Command
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

  defp skip_docs_autolink?(term) do
    String.match?(term, ~r/^ExRatatui\.(Native|Server)(\.|$)/) or
      term == ":ssh_connection.handle_cli_msg/3"
  end
end
