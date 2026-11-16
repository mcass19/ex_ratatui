defmodule ExRatatui.Server.MousePointerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ExRatatui.Event.Mouse
  alias ExRatatui.Runtime
  alias ExRatatui.Server

  defmodule PointerApp do
    use ExRatatui.App

    @impl true
    def mount(opts),
      do: {:ok, Keyword.fetch!(opts, :test_pid), Keyword.get(opts, :mount_opts, [])}

    @impl true
    def render(test_pid, _frame) do
      send(test_pid, :rendered)
      []
    end

    @impl true
    def handle_event(%Mouse{x: x}, state) do
      {:noreply, state, pointer: if(x < 5, do: :pointer, else: :default), render?: false}
    end

    def handle_event({kind, opts}, state), do: {kind, state, opts}

    @impl true
    def handle_info(:crash, _state), do: raise("callback failed")
    def handle_info({kind, opts}, state), do: {kind, state, opts}

    @impl true
    def terminate(reason, test_pid), do: send(test_pid, {:terminated, reason})
  end

  defmodule ReducerApp do
    use ExRatatui.App, runtime: :reducer

    @impl true
    def init(opts), do: {:ok, Keyword.fetch!(opts, :test_pid), pointer: :text, render?: false}

    @impl true
    def update({:event, shape}, state), do: {:noreply, state, pointer: shape, render?: false}

    @impl true
    def render(_state, _frame), do: []
  end

  defp setter do
    test_pid = self()

    fn shape ->
      send(test_pid, {:pointer, shape})
      :ok
    end
  end

  defp start_app(opts \\ []) do
    opts =
      Keyword.merge(
        [mod: PointerApp, test_pid: self(), test_mode: {20, 5}, mouse_pointer_fn: setter()],
        opts
      )

    spec = Supervisor.child_spec({Server, Keyword.put(opts, :name, nil)}, restart: :temporary)
    start_supervised!(spec)
  end

  test "mount opts apply without rendering; omission keeps the current shape" do
    pid = start_app(mount_opts: %{pointer: :text, render?: false})
    assert_receive {:pointer, :text}
    assert Runtime.snapshot(pid).render_count == 0
    refute_received :rendered

    send(pid, {:noreply, [render?: false]})
    assert Runtime.snapshot(pid).render_count == 0
    refute_received {:pointer, _}

    GenServer.stop(pid)
    assert_receive {:pointer, :default}
    assert_receive {:terminated, :normal}
  end

  test "hover bursts deduplicate writes and never redraw, including explicit default" do
    pid = start_app()
    assert_receive :rendered

    for _ <- 1..100 do
      assert :ok = Runtime.inject_event(pid, %Mouse{kind: "moved", x: 1, y: 1})
    end

    assert_receive {:pointer, :pointer}
    refute_received {:pointer, _}
    assert Runtime.snapshot(pid).render_count == 1
    refute_received :rendered

    assert :ok = Runtime.inject_event(pid, %Mouse{kind: "moved", x: 10, y: 1})
    assert_receive {:pointer, :default}
    assert :ok = Runtime.inject_event(pid, %Mouse{kind: "moved", x: 11, y: 1})
    GenServer.stop(pid)
    refute_received {:pointer, _}
  end

  test "info and stopping callbacks apply shapes before termination" do
    pid = start_app()
    send(pid, {:noreply, %{pointer: :grab, render?: false}})
    assert Runtime.snapshot(pid).render_count == 1
    assert_receive {:pointer, :grab}
    monitor = Process.monitor(pid)
    send(pid, {:stop, [pointer: :default]})
    assert_receive {:pointer, :default}
    assert_receive {:terminated, :normal}
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
    refute_received {:pointer, _}
  end

  test "reset is applied before a queued terminal handoff command" do
    pid = start_app(mount_opts: [pointer: :pointer])
    assert_receive {:pointer, :pointer}
    test_pid = self()

    command =
      ExRatatui.Command.async(fn -> send(test_pid, :handoff) end, fn _ -> {:noreply, []} end)

    send(pid, {:noreply, [pointer: :default, render?: false, commands: [command]]})
    assert_receive {:pointer, :default}
    assert_receive :handoff
    GenServer.stop(pid)
    refute_received {:pointer, _}
  end

  test "stopping injected events also apply pointer opts" do
    pid = start_app()
    assert :ok = Runtime.inject_event(pid, {:stop, [pointer: :wait]})
    assert_receive {:pointer, :wait}
    assert_receive {:pointer, :default}
    assert_receive {:terminated, :normal}
  end

  test "a callback crash resets an active shape" do
    pid = start_app(mount_opts: [pointer: :pointer])
    assert_receive {:pointer, :pointer}
    monitor = Process.monitor(pid)
    task_monitor = Process.monitor(:sys.get_state(pid).task_supervisor)

    assert capture_log(fn ->
             send(pid, :crash)
             assert_receive {:DOWN, ^monitor, :process, ^pid, {%RuntimeError{}, _}}, 1000
             assert_receive {:DOWN, ^task_monitor, :process, _task_supervisor, _reason}, 1000
           end) =~ "callback failed"

    assert_receive {:pointer, :default}
    assert_receive {:terminated, {%RuntimeError{}, _}}
  end

  test "unused pointers never write or reset" do
    pid = start_app()
    assert Runtime.snapshot(pid).pointer == nil
    GenServer.stop(pid)
    refute_received {:pointer, _}
  end

  test "test_mode records the shape for the snapshot without writing it" do
    # No injected setter: this is what an app's own test suite runs.
    {:ok, headless} =
      Server.start_link(
        mod: PointerApp,
        name: nil,
        test_pid: self(),
        test_mode: {20, 5},
        mount_opts: [pointer: :pointer]
      )

    assert Runtime.snapshot(headless).pointer == :pointer
    assert :ok = Runtime.inject_event(headless, %Mouse{kind: "moved", x: 10})
    assert Runtime.snapshot(headless).pointer == :default
    assert :ok = Runtime.inject_event(headless, %Mouse{kind: "moved", x: 1})
    assert Runtime.snapshot(headless).pointer == :pointer

    # Cleanup with an active shape and no setter is a no-op.
    assert :ok = GenServer.stop(headless)
    assert_receive {:terminated, :normal}
  end

  test "the snapshot follows the shape written to a live terminal" do
    pid = start_app()
    assert :ok = Runtime.inject_event(pid, %Mouse{kind: "moved", x: 1})
    assert_receive {:pointer, :pointer}
    assert Runtime.snapshot(pid).pointer == :pointer
  end

  test "output errors are best-effort and do not claim a shape was set" do
    pid =
      start_app(
        mouse_pointer_fn: fn _shape -> {:error, :closed} end,
        mount_opts: [pointer: :pointer]
      )

    assert Runtime.snapshot(pid).pointer == nil
    assert :ok = Runtime.inject_event(pid, %Mouse{kind: "moved", x: 1})
    GenServer.stop(pid)
  end

  test "cell, byte-stream, and distributed transports ignore pointer opts" do
    cs = ExRatatui.CellSession.new(20, 5)
    session = ExRatatui.Session.new(20, 5)
    test_pid = self()

    for transport <- [
          {:cell_session, cs, fn _diff -> :ok end,
           fn intent -> send(test_pid, {:intent, intent}) end},
          {:session, session, fn _bytes -> :ok end},
          {:distributed_server, self(), 20, 5}
        ] do
      {:ok, pid} =
        Server.start_link(
          mod: PointerApp,
          name: nil,
          test_pid: self(),
          transport: transport,
          mouse_pointer_fn: setter(),
          mount_opts: [pointer: :pointer]
        )

      assert :ok = Runtime.inject_event(pid, %Mouse{kind: "moved", x: 1})
      send(pid, {:noreply, [pointer: :text, render?: false]})
      assert %{pointer: nil, transport: transport} = Runtime.snapshot(pid)
      assert transport != :local
      GenServer.stop(pid)
    end

    refute_received {:pointer, _}
    refute_received {:intent, _}
  end

  test "reducer init and update share the same pointer behavior" do
    pid = start_app(mod: ReducerApp)
    assert_receive {:pointer, :text}
    assert :ok = Runtime.inject_event(pid, :pointer)
    assert_receive {:pointer, :pointer}
    assert Runtime.snapshot(pid).render_count == 0
    GenServer.stop(pid)
    assert_receive {:pointer, :default}
  end

  test "fixed public shapes map to CSS names; arbitrary payloads are rejected" do
    for shape <- [
          :default,
          :pointer,
          :text,
          :crosshair,
          :move,
          :grab,
          :grabbing,
          :not_allowed,
          :wait,
          :progress
        ] do
      assert ExRatatui.mouse_pointer_name(shape) ==
               String.replace(Atom.to_string(shape), "_", "-")
    end

    for invalid <- [nil, "pointer", :unknown, "pointer\e]0;injected\a"] do
      assert_raise ArgumentError, ~r/invalid mouse pointer shape/, fn ->
        ExRatatui.set_mouse_pointer(invalid)
      end
    end

    assert_raise ArgumentError, ~r/invalid mouse pointer shape/, fn ->
      state = %Server{mod: PointerApp, user_state: self()}
      Server.dispatch_event(state, {:noreply, [pointer: :unknown]})
    end
  end
end
