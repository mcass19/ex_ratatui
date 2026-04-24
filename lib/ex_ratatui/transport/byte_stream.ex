defmodule ExRatatui.Transport.ByteStream do
  @moduledoc """
  Helpers for transports that carry raw terminal bytes to and from a
  remote `ExRatatui.Session`.

  A byte-stream transport is any process that:

    * receives bytes typed by the user (from an SSH channel, an
      xterm.js iframe, a plain TCP socket, …) and pushes them through
      `forward_input/3`; and
    * receives resize notifications from the remote terminal and
      pushes them through `forward_resize/4`.

  Both helpers take care of the Session-level work (parsing bytes
  into events, resizing the Rust-side buffer) and deliver the result
  to the Server using the `t:ExRatatui.Transport.to_server/0`
  messages `{:ex_ratatui_event, _}` and `{:ex_ratatui_resize, _, _}`.

  `ExRatatui.SSH` uses these helpers; `kino_ex_ratatui` will too.
  Distributed does not — it ships widget trees, not bytes.
  """

  alias ExRatatui.Event
  alias ExRatatui.Session

  @doc """
  Feeds `bytes` into `session`, dispatches the resulting events to
  `server`, and returns the list of decoded events.

  Resize events synthesized by the parser (e.g. from a `CSI 14 t`
  reply) are absorbed: they resize the session in place and surface
  to the Server as `{:ex_ratatui_resize, w, h}` instead of a regular
  `Event.Resize` message. All other events flow through as
  `{:ex_ratatui_event, event}`.

  Callers get the events back so they can inspect them without a
  second parse pass — `ExRatatui.SSH`, for instance, uses an empty
  result together with a lone `0x1B` in `bytes` as the trigger to
  arm its bare-Esc timeout.
  """
  @spec forward_input(Session.t(), pid(), iodata()) :: [Event.t()]
  def forward_input(%Session{} = session, server, bytes) when is_pid(server) do
    events = Session.feed_input(session, bytes)
    Enum.each(events, &dispatch_event(&1, session, server))
    events
  end

  @doc """
  Resizes `session` to `width` × `height` and notifies `server` with
  `{:ex_ratatui_resize, width, height}`.

  Use this for resize signals delivered out-of-band by the transport
  itself (SSH `window_change`, xterm.js FitAddon resize, …). Resize
  events that come back from the byte parser are handled inside
  `forward_input/3` and don't need a separate call.
  """
  @spec forward_resize(Session.t(), pid(), pos_integer(), pos_integer()) :: :ok
  def forward_resize(%Session{} = session, server, width, height)
      when is_pid(server) and is_integer(width) and width > 0 and is_integer(height) and
             height > 0 do
    _ = Session.resize(session, width, height)
    send(server, {:ex_ratatui_resize, width, height})
    :ok
  end

  defp dispatch_event(%Event.Resize{width: w, height: h}, %Session{} = session, server)
       when is_integer(w) and w > 0 and is_integer(h) and h > 0 do
    forward_resize(session, server, w, h)
  end

  defp dispatch_event(event, %Session{}, server) do
    send(server, {:ex_ratatui_event, event})
    :ok
  end
end
