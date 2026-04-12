defmodule ExRatatui.DistributedTest do
  use ExUnit.Case, async: true

  alias ExRatatui.{Distributed, Distributed.Listener}

  describe "ensure_connected/1" do
    test "returns error when trying to attach to self" do
      assert {:error, :cannot_attach_to_self} = Distributed.ensure_connected(Node.self())
    end

    test "returns error when distribution is not started and node is not alive" do
      # When the current node is not distributed, Node.connect returns :ignored
      # We test the shape — in CI the node may or may not be alive
      result = Distributed.ensure_connected(:nonexistent@nowhere)

      assert {:error, reason} = result
      assert reason in [:distribution_not_started, {:connect_failed, :nonexistent@nowhere}]
    end
  end

  describe "resolve_local_size/1" do
    test "uses test_mode dimensions when provided" do
      assert {:ok, 120, 40} = Distributed.resolve_local_size(test_mode: {120, 40})
    end

    test "resolves terminal size when no test_mode" do
      result = Distributed.resolve_local_size([])

      case result do
        {:ok, w, h} ->
          assert is_integer(w) and is_integer(h)

        {:error, {:terminal_size_failed, _}} ->
          # Expected in CI: no TTY
          :ok
      end
    end
  end

  describe "start_remote_session/5" do
    test "returns rpc_failed for unreachable node" do
      assert {:error, {:rpc_failed, _reason}} =
               Distributed.start_remote_session(
                 :nonexistent@nowhere,
                 Listener,
                 self(),
                 80,
                 24
               )
    end
  end

  describe "start_local_client/1" do
    test "starts a Client process" do
      {:ok, pid} =
        Distributed.start_local_client(test_mode: {80, 24})

      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "forwards poll_interval option" do
      {:ok, pid} =
        Distributed.start_local_client(test_mode: {80, 24}, poll_interval: 32)

      state = :sys.get_state(pid)
      assert state.poll_interval == 32

      GenServer.stop(pid)
    end
  end

  describe "attach/3" do
    test "returns error from ensure_connected when node is unreachable" do
      # ensure_connected fails before start_local_client is called
      result =
        Distributed.attach(:nonexistent@nowhere, SomeApp, test_mode: {80, 24})

      assert {:error, reason} = result
      assert reason == :distribution_not_started or match?({:connect_failed, _}, reason)
    end
  end

  describe "Listener.start_session/4 error handling" do
    test "returns error when mount fails" do
      # Simulate an RPC that returns {:error, reason} by calling directly
      # on a Listener with a failing mount app
      {:ok, listener} =
        Listener.start_link(
          mod: FailingMountApp,
          name: nil
        )

      result =
        Listener.start_session(self(), 80, 24, listener)

      assert {:error, _reason} = result

      Supervisor.stop(listener)
    end
  end

  defmodule FailingMountApp do
    use ExRatatui.App

    @impl true
    def mount(_opts), do: {:error, :boom}

    @impl true
    def render(_state, _frame), do: []

    @impl true
    def handle_event(_event, state), do: {:noreply, state}
  end
end
