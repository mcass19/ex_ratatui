defmodule ExRatatui.TransportTest do
  @moduledoc """
  Tests for the public surface of `ExRatatui.Transport` — currently
  the `start_server/1` entrypoint that custom transports use to boot
  the runtime without reaching into `@moduledoc false` internals.
  """

  use ExUnit.Case, async: true

  alias ExRatatui.Frame
  alias ExRatatui.Session
  alias ExRatatui.Test.ServerApps.Echo

  describe "start_server/1" do
    test "boots a server under the :session transport and renders a frame" do
      session = Session.new(40, 10)
      test_pid = self()
      writer = fn bytes -> send(test_pid, {:writer_bytes, bytes}) end

      {:ok, pid} =
        ExRatatui.Transport.start_server(
          mod: Echo,
          name: nil,
          test_pid: test_pid,
          transport: {:session, session, writer}
        )

      assert_receive {:mounted, opts}, 1000
      assert opts[:transport] == :session
      assert opts[:width] == 40
      assert opts[:height] == 10

      assert_receive {:rendered, 0, %Frame{width: 40, height: 10}}, 1000
      assert_receive {:writer_bytes, bytes}, 1000
      assert is_binary(bytes) and byte_size(bytes) > 0

      GenServer.stop(pid)
      assert_receive {:terminated, :normal}, 1000
    end

    test "raises on non-list opts" do
      assert_raise FunctionClauseError, fn ->
        ExRatatui.Transport.start_server(%{mod: Echo})
      end
    end
  end
end
