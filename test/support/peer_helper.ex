defmodule ExRatatui.Test.PeerHelper do
  @moduledoc false
  # Helper for distributed integration tests.
  # Compiled to disk so it can be loaded on :peer nodes.

  @doc false
  def start_listener_unlinked(opts) do
    # start_link links the Listener to the caller. When called via
    # :rpc.call, the caller is the RPC server process which exits when
    # the call returns — killing the Listener. Unlink immediately.
    {:ok, pid} = ExRatatui.Distributed.Listener.start_link(opts)
    Process.unlink(pid)
    {:ok, pid}
  end
end
