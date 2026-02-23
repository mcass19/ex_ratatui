defmodule ExRatatui.Native do
  @moduledoc false

  version = Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :ex_ratatui,
    crate: "ex_ratatui",
    base_url: "https://github.com/mcass19/ex_ratatui/releases/download/v#{version}",
    force_build: System.get_env("EX_RATATUI_BUILD") in ["1", "true"],
    version: version,
    targets: ~w(
      aarch64-apple-darwin
      aarch64-unknown-linux-gnu
      aarch64-unknown-linux-musl
      arm-unknown-linux-gnueabihf
      riscv64gc-unknown-linux-gnu
      x86_64-apple-darwin
      x86_64-pc-windows-gnu
      x86_64-pc-windows-msvc
      x86_64-unknown-linux-gnu
      x86_64-unknown-linux-musl
    ),
    nif_versions: ["2.16", "2.17"]

  # Terminal lifecycle

  @doc false
  # Enters raw mode, alternate screen, and creates a crossterm-backed terminal.
  # Returns a terminal reference (ResourceArc).
  def init_terminal, do: :erlang.nif_error(:not_loaded)

  @doc false
  # Leaves alternate screen and disables raw mode. Safe to call multiple times.
  def restore_terminal(_terminal_ref), do: :erlang.nif_error(:not_loaded)

  @doc false
  # Returns `{width, height}` of the current terminal.
  def terminal_size, do: :erlang.nif_error(:not_loaded)

  # Rendering

  @doc false
  # Draws a list of `{widget_map, rect_map}` tuples in a single frame.
  def draw_frame(_terminal_ref, _commands), do: :erlang.nif_error(:not_loaded)

  # Events

  @doc false
  # Polls for a terminal event with timeout (ms). Runs on DirtyIo scheduler.
  def poll_event(_timeout_ms), do: :erlang.nif_error(:not_loaded)

  # Layout

  @doc false
  # Splits a rect into sub-rects given a direction and constraints.
  def layout_split(_area, _direction, _constraints), do: :erlang.nif_error(:not_loaded)

  # Test backend

  @doc false
  # Creates a headless test terminal with given dimensions.
  # Returns a terminal reference (ResourceArc).
  def init_test_terminal(_width, _height), do: :erlang.nif_error(:not_loaded)

  @doc false
  # Returns the test terminal's buffer contents as a string.
  def get_buffer_content(_terminal_ref), do: :erlang.nif_error(:not_loaded)
end
