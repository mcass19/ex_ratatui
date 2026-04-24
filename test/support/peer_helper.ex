defmodule ExRatatui.Test.PeerHelper do
  @moduledoc false
  # Helper for distributed integration tests.
  # Compiled to disk so it can be loaded on :peer nodes.

  alias ExRatatui.Distributed.Listener

  @doc false
  def start_listener_unlinked(opts) do
    # `:telemetry` is not started automatically on peer nodes — ensure
    # it's up before any Server instrumentation fires.
    {:ok, _} = Application.ensure_all_started(:telemetry)

    # start_link links the Listener to the caller. When called via
    # :rpc.call, the caller is the RPC server process which exits when
    # the call returns — killing the Listener. Unlink immediately.
    {:ok, pid} = Listener.start_link(opts)
    Process.unlink(pid)
    {:ok, pid}
  end
end
