defmodule ExRatatui.Distributed.ListenerTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Distributed.Listener
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph

  defmodule ListenerApp do
    use ExRatatui.App

    @impl true
    def mount(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:mounted, self(), opts})
      {:ok, %{test_pid: test_pid}}
    end

    @impl true
    def render(state, frame) do
      send(state.test_pid, {:rendered, frame})

      [
        {%Paragraph{text: "distributed"},
         %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}
      ]
    end

    @impl true
    def handle_event(event, state) do
      send(state.test_pid, {:event, event})
      {:noreply, state}
    end
  end

  describe "start_link/1" do
    test "starts the listener supervisor" do
      {:ok, pid} =
        Listener.start_link(
          mod: ListenerApp,
          name: nil
        )

      assert Process.alive?(pid)
      Supervisor.stop(pid)
    end

    test "starts with a registered name" do
      name = :"listener_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Listener.start_link(
          mod: ListenerApp,
          name: name
        )

      assert Process.whereis(name) == pid
      Supervisor.stop(pid)
    end
  end

  describe "session_sup/1" do
    test "returns the DynamicSupervisor pid" do
      {:ok, pid} =
        Listener.start_link(
          mod: ListenerApp,
          name: nil
        )

      sup = Listener.session_sup(pid)
      assert is_pid(sup)
      assert Process.alive?(sup)

      Supervisor.stop(pid)
    end
  end

  describe "start_session/4" do
    test "spawns a Server in :distributed_server mode" do
      {:ok, listener} =
        Listener.start_link(
          mod: ListenerApp,
          name: nil,
          app_opts: [test_pid: self()]
        )

      {:ok, server_pid} = Listener.start_session(self(), 80, 24, listener)
      assert is_pid(server_pid)
      assert Process.alive?(server_pid)

      # The server should have mounted and sent initial draw
      assert_receive {:mounted, ^server_pid, opts}, 1000
      assert opts[:transport] == :distributed
      assert opts[:width] == 80
      assert opts[:height] == 24

      assert_receive {:rendered, _frame}, 1000
      assert_receive {:ex_ratatui_draw, widgets}, 1000
      assert [{%Paragraph{text: "distributed"}, %Rect{}}] = widgets

      GenServer.stop(server_pid)
      Supervisor.stop(listener)
    end

    test "app_opts are merged into mount opts" do
      {:ok, listener} =
        Listener.start_link(
          mod: ListenerApp,
          name: nil,
          app_opts: [test_pid: self(), custom: :value]
        )

      {:ok, server_pid} = Listener.start_session(self(), 40, 10, listener)

      assert_receive {:mounted, ^server_pid, opts}, 1000
      assert opts[:custom] == :value

      GenServer.stop(server_pid)
      Supervisor.stop(listener)
    end

    test "multiple sessions can run concurrently" do
      {:ok, listener} =
        Listener.start_link(
          mod: ListenerApp,
          name: nil,
          app_opts: [test_pid: self()]
        )

      {:ok, pid1} = Listener.start_session(self(), 80, 24, listener)
      {:ok, pid2} = Listener.start_session(self(), 40, 10, listener)

      assert pid1 != pid2
      assert Process.alive?(pid1)
      assert Process.alive?(pid2)

      GenServer.stop(pid1)
      GenServer.stop(pid2)
      Supervisor.stop(listener)
    end
  end

  describe "session_sup/0 with default name" do
    test "uses ExRatatui.Distributed.Listener as default" do
      {:ok, _pid} =
        Listener.start_link(
          mod: ListenerApp,
          name: Listener
        )

      sup = Listener.session_sup()
      assert is_pid(sup)
      assert Process.alive?(sup)

      Supervisor.stop(Listener)
    end
  end

  describe "start_session/3 with default name" do
    test "uses ExRatatui.Distributed.Listener as default" do
      {:ok, _pid} =
        Listener.start_link(
          mod: ListenerApp,
          name: Listener,
          app_opts: [test_pid: self()]
        )

      {:ok, server_pid} = Listener.start_session(self(), 50, 15)
      assert is_pid(server_pid)

      assert_receive {:mounted, ^server_pid, opts}, 1000
      assert opts[:width] == 50
      assert opts[:height] == 15

      GenServer.stop(server_pid)
      Supervisor.stop(Listener)
    end
  end

  describe "session_sup/1 with registered name" do
    test "resolves via registered name" do
      name = :"listener_named_#{System.unique_integer([:positive])}"

      {:ok, _pid} =
        Listener.start_link(
          mod: ListenerApp,
          name: name
        )

      sup = Listener.session_sup(name)
      assert is_pid(sup)
      assert Process.alive?(sup)

      Supervisor.stop(name)
    end
  end

  describe "start_session/4 with registered name" do
    test "works via registered listener name" do
      name = :"listener_session_#{System.unique_integer([:positive])}"

      {:ok, _pid} =
        Listener.start_link(
          mod: ListenerApp,
          name: name,
          app_opts: [test_pid: self()]
        )

      {:ok, server_pid} = Listener.start_session(self(), 60, 20, name)
      assert is_pid(server_pid)

      assert_receive {:mounted, ^server_pid, opts}, 1000
      assert opts[:width] == 60
      assert opts[:height] == 20

      GenServer.stop(server_pid)
      Supervisor.stop(name)
    end
  end
end
