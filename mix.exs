defmodule ExRatatui.MixProject do
  use Mix.Project

  @description "Elixir bindings for the Rust ratatui terminal UI library"
  @source_url "https://github.com/mcass19/ex_ratatui"
  @changelog_url @source_url <> "/blob/main/CHANGELOG.md"
  @version "0.10.2"

  def project do
    [
      app: :ex_ratatui,
      description: @description,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() == :prod,
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
          ExRatatui.Test.PeerHelper,
          ExRatatui.Test.PeerRichApp,
          ExRatatui.Test.PeerWidgetsApp,
          ExRatatui.Test.CrossTransportApp,
          # shared server test fixtures
          ExRatatui.Test.ServerApps.Echo,
          ExRatatui.Test.ServerApps.FailingMount,
          ExRatatui.Test.ServerApps.StopOnAnyEvent,
          ExRatatui.Test.ServerApps.Intents,
          ExRatatui.Test.SshHelper
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
      extra_applications: [:logger, :ssh, :telemetry]
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
      {:telemetry, "~> 1.0"},

      # Optional
      {:rustler, ">= 0.0.0", optional: true},

      # Dev
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},

      # Test
      {:stream_data, "~> 1.1", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @changelog_url
      },
      keywords: ~w(tui terminal ratatui cli ssh nerves distributed otp),
      files: ~w(
        lib native assets/logo.png .formatter.exs mix.exs README.md LICENSE CHANGELOG.md
        usage-rules.md checksum-Elixir.ExRatatui.Native.exs
      ),
      exclude_patterns: ~w(native/ex_ratatui/target)
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/logo.png",
      source_ref: "v#{@version}",
      extras: [
        "README.md": [title: "Overview"],
        "usage-rules.md": [title: "Usage Rules (for AI agents)"],
        "guides/introduction/getting_started.md": [title: "Getting Started"],
        "examples/README.md": [title: "Examples", filename: "examples"],
        "guides/core/building_uis.md": [title: "Building UIs"],
        "guides/core/custom_widgets.md": [title: "Custom Widgets"],
        "guides/core/images.md": [title: "Images"],
        "guides/core/paste_and_clipboard.md": [title: "Paste and Clipboard"],
        "guides/runtimes/callback_runtime.md": [title: "Callback Runtime"],
        "guides/runtimes/reducer_runtime.md": [title: "Reducer Runtime"],
        "guides/runtimes/state_machines.md": [title: "State Machine Patterns"],
        "guides/transports/transports.md": [title: "Transports"],
        "guides/transports/ssh_transport.md": [title: "Running TUIs over SSH"],
        "guides/transports/distributed_transport.md": [
          title: "Running TUIs over Erlang Distribution"
        ],
        "guides/transports/custom_transports.md": [title: "Custom Transports"],
        "guides/transports/cell_session.md": [title: "Rendering to Non-Terminal Surfaces"],
        "guides/internals/architecture.md": [title: "Architecture"],
        "guides/internals/testing.md": [title: "Testing"],
        "guides/internals/debugging.md": [title: "Debugging"],
        "guides/internals/performance.md": [title: "Performance"],
        "guides/internals/telemetry.md": [title: "Telemetry"],
        "guides/cheatsheets/widgets.cheatmd": [title: "Widgets Cheatsheet"],
        "CONTRIBUTING.md": [title: "Contributing"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      groups_for_extras: [
        Introduction: ["guides/introduction/getting_started.md", "examples/README.md"],
        "Building UIs": Path.wildcard("guides/core/*.md"),
        Runtimes: Path.wildcard("guides/runtimes/*.md"),
        Transports: Path.wildcard("guides/transports/*.md"),
        "Going Deeper": Path.wildcard("guides/internals/*.md"),
        Cheatsheets: Path.wildcard("guides/cheatsheets/*.cheatmd")
      ],
      groups_for_modules: [
        Core: [
          ExRatatui,
          ExRatatui.Session,
          ExRatatui.CellSession,
          ExRatatui.CellSession.Cell,
          ExRatatui.CellSession.Snapshot,
          ExRatatui.CellSession.Diff
        ],
        Observability: [
          ExRatatui.Telemetry
        ],
        Application: [
          ExRatatui.App
        ],
        "Reducer Runtime": [
          ExRatatui.Command,
          ExRatatui.Subscription,
          ExRatatui.Runtime
        ],
        Layout: [
          ExRatatui.Frame,
          ExRatatui.Layout,
          ExRatatui.Layout.Rect,
          ExRatatui.Layout.Padding
        ],
        Style: [
          ExRatatui.Style,
          ExRatatui.Theme
        ],
        "Rich Text": [
          ExRatatui.Text,
          ExRatatui.Text.Line,
          ExRatatui.Text.Span
        ],
        Events: [
          ExRatatui.Event,
          ExRatatui.Event.Key,
          ExRatatui.Event.Mouse,
          ExRatatui.Event.Resize,
          ExRatatui.Event.Paste,
          ExRatatui.Event.FocusGained,
          ExRatatui.Event.FocusLost
        ],
        Focus: [
          ExRatatui.Focus
        ],
        Widgets: [
          ExRatatui.Widgets.Paragraph,
          ExRatatui.Widgets.Block,
          ExRatatui.Widgets.Block.Title,
          ExRatatui.Widgets.List,
          ExRatatui.Widgets.Table,
          ExRatatui.Widgets.Gauge,
          ExRatatui.Widgets.LineGauge,
          ExRatatui.Widgets.Sparkline,
          ExRatatui.Widgets.Calendar,
          ExRatatui.Widgets.Tabs,
          ExRatatui.Widgets.Scrollbar,
          ExRatatui.Widgets.Checkbox,
          ExRatatui.Widgets.TextInput,
          ExRatatui.Widgets.Clear,
          ExRatatui.Widgets.Markdown,
          ExRatatui.Widgets.Textarea,
          ExRatatui.Widgets.Throbber,
          ExRatatui.Widgets.Popup,
          ExRatatui.Widgets.WidgetList
        ],
        "Widgets: Bar Chart": [
          ExRatatui.Widgets.BarChart,
          ExRatatui.Widgets.Bar,
          ExRatatui.Widgets.BarGroup
        ],
        "Widgets: Canvas": [
          ExRatatui.Widgets.Canvas,
          ExRatatui.Widgets.Canvas.Circle,
          ExRatatui.Widgets.Canvas.Label,
          ExRatatui.Widgets.Canvas.Line,
          ExRatatui.Widgets.Canvas.Map,
          ExRatatui.Widgets.Canvas.Points,
          ExRatatui.Widgets.Canvas.Rectangle
        ],
        "Widgets: Chart": [
          ExRatatui.Widgets.Chart,
          ExRatatui.Widgets.Chart.Axis,
          ExRatatui.Widgets.Chart.Dataset
        ],
        "Widgets: Slash Commands": [
          ExRatatui.Widgets.SlashCommands,
          ExRatatui.Widgets.SlashCommands.Command
        ],
        "Widgets: Image": [
          ExRatatui.Image,
          ExRatatui.Widgets.Image
        ],
        "Widgets: BigText": [
          ExRatatui.BigText,
          ExRatatui.Widgets.BigText
        ],
        "Widgets: Code": [
          ExRatatui.CodeBlock,
          ExRatatui.Widgets.CodeBlock
        ],
        "Custom Widgets": [
          ExRatatui.Widget
        ],
        Transport: [
          ExRatatui.Transport,
          ExRatatui.Transport.ByteStream
        ],
        "SSH Transport": [
          ExRatatui.SSH,
          ExRatatui.SSH.Daemon
        ],
        "Distribution Transport": [
          ExRatatui.Distributed,
          ExRatatui.Distributed.Listener
        ]
      ]
    ]
  end
end
