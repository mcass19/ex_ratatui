defmodule ExRatatui.Distributed.IntegrationTest do
  use ExUnit.Case

  @moduletag :distributed

  alias ExRatatui.Distributed
  alias ExRatatui.Distributed.Listener
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph

  @peer_app ExRatatui.Test.PeerApp

  # Excluded by default via test_helper.exs.
  # Run with: elixir --sname test -S mix test --only distributed
  setup do
    unless Node.alive?() do
      flunk(
        "Node is not distributed. " <>
          "Run with: elixir --sname test -S mix test --only distributed"
      )
    end

    # Start a peer node with code paths so it can see all compiled
    # BEAM files (ex_ratatui, deps, Elixir stdlib, and test/support).
    code_paths =
      Path.wildcard("_build/test/lib/*/ebin") ++
        Path.wildcard("#{:code.lib_dir(:elixir)}/ebin")

    args = Enum.flat_map(code_paths, fn path -> [~c"-pa", String.to_charlist(path)] end)

    peer_name = :"peer_#{System.unique_integer([:positive])}"
    {:ok, peer_pid, peer_node} = :peer.start(%{name: peer_name, args: args})

    on_exit(fn -> :peer.stop(peer_pid) end)

    {:ok, peer_node: peer_node, peer_pid: peer_pid}
  end

  defp start_peer_listener(peer_node, extra_opts) do
    opts = [mod: @peer_app, name: nil] ++ extra_opts

    :rpc.call(
      peer_node,
      ExRatatui.Test.PeerHelper,
      :start_listener_unlinked,
      [opts]
    )
  end

  describe "full roundtrip via Listener + Client" do
    test "mount, render, draw, events flow across nodes", %{peer_node: peer_node} do
      {:ok, listener} = start_peer_listener(peer_node, app_opts: [test_pid: self()])

      {:ok, server_pid} =
        :rpc.call(peer_node, Listener, :start_session, [self(), 80, 24, listener])

      # Server mounted on remote node, notified us
      assert_receive {:mounted, ^server_pid, opts}, 2000
      assert opts[:transport] == :distributed
      assert opts[:width] == 80
      assert opts[:height] == 24

      # Server rendered and sent us the widget list
      assert_receive {:ex_ratatui_draw, widgets}, 2000
      assert [{%Paragraph{text: "count: 0"}, %Rect{width: 80, height: 24}}] = widgets

      # Send an event — should trigger handle_event, re-render, new draw
      send(
        server_pid,
        {:ex_ratatui_event, %ExRatatui.Event.Key{code: "a", modifiers: [], kind: "press"}}
      )

      assert_receive {:ex_ratatui_draw, widgets2}, 2000
      assert [{%Paragraph{text: "count: 1"}, %Rect{}}] = widgets2

      # Send resize — should trigger re-render with new dimensions
      send(server_pid, {:ex_ratatui_resize, 120, 40})

      assert_receive {:ex_ratatui_draw, widgets3}, 2000
      assert [{%Paragraph{}, %Rect{width: 120, height: 40}}] = widgets3

      # Monitor before sending quit so we don't miss the exit
      ref = Process.monitor(server_pid)

      send(
        server_pid,
        {:ex_ratatui_event, %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}}
      )

      assert_receive {:DOWN, ^ref, :process, ^server_pid, :normal}, 2000
      assert_receive {:terminated, :normal}, 2000

      :rpc.call(peer_node, Supervisor, :stop, [listener])
    end

    test "server stops when client disconnects", %{peer_node: peer_node} do
      {:ok, listener} = start_peer_listener(peer_node, app_opts: [test_pid: self()])

      # Use a proxy process as client so we can kill it
      proxy = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, server_pid} =
        :rpc.call(peer_node, Listener, :start_session, [proxy, 80, 24, listener])

      assert_receive {:mounted, ^server_pid, _opts}, 2000

      ref = Process.monitor(server_pid)
      Process.exit(proxy, :kill)

      assert_receive {:DOWN, ^ref, :process, ^server_pid, :normal}, 2000

      :rpc.call(peer_node, Supervisor, :stop, [listener])
    end

    test "multiple concurrent sessions on the same listener", %{peer_node: peer_node} do
      {:ok, listener} = start_peer_listener(peer_node, app_opts: [test_pid: self()])

      {:ok, server1} =
        :rpc.call(peer_node, Listener, :start_session, [self(), 80, 24, listener])

      {:ok, server2} =
        :rpc.call(peer_node, Listener, :start_session, [self(), 40, 10, listener])

      assert server1 != server2

      # Both should mount independently
      assert_receive {:mounted, ^server1, opts1}, 2000
      assert opts1[:width] == 80

      assert_receive {:mounted, ^server2, opts2}, 2000
      assert opts2[:width] == 40

      # Both send initial draws
      assert_receive {:ex_ratatui_draw, _}, 2000
      assert_receive {:ex_ratatui_draw, _}, 2000

      GenServer.stop(server1)
      GenServer.stop(server2)
      :rpc.call(peer_node, Supervisor, :stop, [listener])
    end
  end

  describe "Distributed.ensure_connected/1" do
    test "succeeds when already connected", %{peer_node: peer_node} do
      assert peer_node in Node.list()
      assert :ok = Distributed.ensure_connected(peer_node)
    end
  end

  describe "Distributed.start_remote_session/5" do
    test "starts a remote session via RPC", %{peer_node: peer_node} do
      {:ok, listener} = start_peer_listener(peer_node, app_opts: [test_pid: self()])

      {:ok, remote_pid} =
        Distributed.start_remote_session(peer_node, listener, self(), 80, 24)

      assert is_pid(remote_pid)
      assert node(remote_pid) == peer_node

      assert_receive {:mounted, ^remote_pid, _opts}, 2000

      GenServer.stop(remote_pid)
      :rpc.call(peer_node, Supervisor, :stop, [listener])
    end

    test "returns error when listener is not running", %{peer_node: peer_node} do
      assert {:error, {:rpc_failed, _}} =
               Distributed.start_remote_session(
                 peer_node,
                 :nonexistent_listener,
                 self(),
                 80,
                 24
               )
    end
  end

  describe "Distributed.attach/3 end-to-end" do
    test "attaches, receives draws, and exits cleanly", %{peer_node: peer_node} do
      {:ok, listener} = start_peer_listener(peer_node, app_opts: [test_pid: self()])

      test_pid = self()

      # Monitor before spawning so we don't race the exit
      attach_pid =
        spawn(fn ->
          result =
            Distributed.attach(peer_node, @peer_app,
              listener: listener,
              test_mode: {80, 24}
            )

          send(test_pid, {:attach_result, result})
        end)

      ref = Process.monitor(attach_pid)

      # The remote server should mount (test_pid receives :mounted
      # because PeerApp sends it from mount/1)
      assert_receive {:mounted, server_pid, _opts}, 2000
      assert node(server_pid) == peer_node

      # Send quit event to stop the server — the client detects
      # the DOWN and exits, unblocking attach/3
      send(
        server_pid,
        {:ex_ratatui_event, %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}}
      )

      assert_receive {:attach_result, :ok}, 5000
      assert_receive {:terminated, :normal}, 2000
      assert_receive {:DOWN, ^ref, :process, ^attach_pid, :normal}, 2000

      :rpc.call(peer_node, Supervisor, :stop, [listener])
    end
  end

  describe "Distributed.attach/3 error path" do
    test "returns error and cleans up client when listener is not running", %{
      peer_node: peer_node
    } do
      # No listener started on the peer — start_remote_session will fail.
      # attach/3 must stop the already-started Client and return the error.
      result =
        Distributed.attach(peer_node, @peer_app,
          listener: :nonexistent_listener,
          test_mode: {80, 24}
        )

      assert {:error, {:rpc_failed, _}} = result
    end
  end

  describe "handle_info forwarding" do
    test "custom messages reach the app's handle_info on the remote node", %{
      peer_node: peer_node
    } do
      {:ok, listener} = start_peer_listener(peer_node, app_opts: [test_pid: self()])

      {:ok, server_pid} =
        :rpc.call(peer_node, Listener, :start_session, [self(), 80, 24, listener])

      assert_receive {:mounted, ^server_pid, _opts}, 2000

      send(server_pid, {:custom_msg, :hello_from_client})

      assert_receive {:got_custom, :hello_from_client}, 2000

      GenServer.stop(server_pid)
      :rpc.call(peer_node, Supervisor, :stop, [listener])
    end
  end
end
