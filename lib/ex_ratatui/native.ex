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

  # TextInput (stateful widget)

  @doc false
  # Creates a new TextInput state. Returns a ResourceArc reference.
  def text_input_new, do: :erlang.nif_error(:not_loaded)

  @doc false
  # Handles a key event on the TextInput state.
  def text_input_handle_key(_state_ref, _key_code), do: :erlang.nif_error(:not_loaded)

  @doc false
  # Returns the current text value from the TextInput state.
  def text_input_get_value(_state_ref), do: :erlang.nif_error(:not_loaded)

  @doc false
  # Sets the text value on the TextInput state.
  def text_input_set_value(_state_ref, _value), do: :erlang.nif_error(:not_loaded)

  @doc false
  # Returns the current cursor position from the TextInput state.
  def text_input_cursor(_state_ref), do: :erlang.nif_error(:not_loaded)

  # Session (per-connection terminal with pluggable I/O)

  @doc false
  # Creates a new session backed by an in-memory writer. No OS terminal state
  # is touched. Returns a session reference (ResourceArc).
  def session_new(_width, _height), do: :erlang.nif_error(:not_loaded)

  @doc false
  # Drops the session's inner ratatui terminal. Idempotent.
  def session_close(_session_ref), do: :erlang.nif_error(:not_loaded)

  @doc false
  # Renders a list of `{widget_map, rect_map}` tuples into the session's
  # in-memory writer. Bytes accumulate until drained via `session_take_output/1`.
  def session_draw(_session_ref, _commands), do: :erlang.nif_error(:not_loaded)

  @doc false
  # Drains and returns the session's pending output bytes as a binary.
  def session_take_output(_session_ref), do: :erlang.nif_error(:not_loaded)

  @doc false
  # Feeds raw transport bytes through the session's ANSI parser. Returns
  # a list of `{:key, code, modifiers, kind} | {:mouse, ...} | {:resize, ...}`
  # tagged tuples — the same shape `poll_event/1` returns. Bytes that only
  # partially form an escape sequence stay buffered for the next call.
  def session_feed_input(_session_ref, _bytes), do: :erlang.nif_error(:not_loaded)

  @doc false
  # Resizes the session's viewport. Triggers a buffer clear that the
  # transport will see in the next `session_take_output/1` drain.
  def session_resize(_session_ref, _width, _height), do: :erlang.nif_error(:not_loaded)

  @doc false
  # Returns the session's current `{width, height}`.
  def session_size(_session_ref), do: :erlang.nif_error(:not_loaded)

  # Textarea (stateful multiline widget)

  @doc false
  def textarea_new, do: :erlang.nif_error(:not_loaded)

  @doc false
  def textarea_handle_key(_state_ref, _key_code, _modifiers), do: :erlang.nif_error(:not_loaded)

  @doc false
  def textarea_get_value(_state_ref), do: :erlang.nif_error(:not_loaded)

  @doc false
  def textarea_set_value(_state_ref, _value), do: :erlang.nif_error(:not_loaded)

  @doc false
  def textarea_cursor(_state_ref), do: :erlang.nif_error(:not_loaded)

  @doc false
  def textarea_line_count(_state_ref), do: :erlang.nif_error(:not_loaded)
end
