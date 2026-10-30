defmodule ExRatatui.AppTest do
  use ExUnit.Case, async: true

  import ExRatatui.Test.Untyped

  alias ExRatatui.{App, Command, Runtime, Subscription}
  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph

  defmodule SampleApp do
    use ExRatatui.App

    @impl true
    def mount(_opts), do: {:ok, %{count: 0}}

    @impl true
    def render(state, _frame), do: [{:widget, state}]

    @impl true
    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule ReducerSampleApp do
    use ExRatatui.App, runtime: :reducer

    @impl true
    def init(opts), do: {:ok, %{opts: opts}}

    @impl true
    def render(_state, _frame), do: []

    @impl true
    def update(msg, state), do: {:noreply, {msg, state}}
  end

  test "using ExRatatui.App defines the behaviour" do
    assert function_exported?(SampleApp, :mount, 1)
    assert function_exported?(SampleApp, :render, 2)
    assert function_exported?(SampleApp, :handle_event, 2)
    assert function_exported?(SampleApp, :handle_info, 2)
  end

  test "default handle_info/2 returns {:noreply, state}" do
    assert {:noreply, :my_state} = SampleApp.handle_info(:unknown_msg, :my_state)
  end

  test "reducer_handle_event/3 wraps events before delegating to update/2" do
    assert {:noreply, {{:event, :ping}, :state}} =
             ExRatatui.App.reducer_handle_event(ReducerSampleApp, :ping, :state)
  end

  test "using ExRatatui.App rejects unsupported runtimes" do
    quoted =
      quote do
        defmodule ExRatatui.AppTest.InvalidRuntimeApp do
          use ExRatatui.App, runtime: :invalid
        end
      end

    assert_raise ArgumentError, "unsupported ExRatatui.App runtime: :invalid", fn ->
      Code.eval_quoted(quoted)
    end
  end

  test "mount returns initial state" do
    assert {:ok, %{count: 0}} = SampleApp.mount([])
  end

  test "child_spec is generated correctly" do
    spec = SampleApp.child_spec([])
    assert spec.id == SampleApp
    assert spec.type == :worker
    assert spec.restart == :transient
  end

  # -- Integration tests: App -> child_spec -> Server chain --

  defmodule SupervisedApp do
    use ExRatatui.App

    @impl true
    def mount(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:supervised_mounted, opts})
      {:ok, %{test_pid: test_pid}}
    end

    @impl true
    def render(state, frame) do
      send(state.test_pid, {:supervised_rendered, frame})
      []
    end

    @impl true
    def handle_event(_event, state), do: {:noreply, state}
  end

  test "start_link starts the server via App module" do
    {:ok, pid} = SupervisedApp.start_link(name: nil, test_pid: self(), test_mode: {40, 10})

    assert_receive {:supervised_mounted, opts}, 1000
    assert Keyword.get(opts, :test_pid) == self()
    assert Process.alive?(pid)

    GenServer.stop(pid)
  end

  test "child_spec has correct start tuple" do
    spec = SupervisedApp.child_spec(name: nil, test_pid: self(), test_mode: {40, 10})

    assert spec.id == SupervisedApp

    assert spec.start ==
             {SupervisedApp, :start_link, [[name: nil, test_pid: self(), test_mode: {40, 10}]]}

    assert spec.type == :worker
    assert spec.restart == :transient
  end

  describe "transport dispatch" do
    test "default transport is :local" do
      # No explicit :transport — must still go through Server.start_link.
      {:ok, pid} =
        SupervisedApp.start_link(name: nil, test_pid: self(), test_mode: {40, 10})

      assert_receive {:supervised_mounted, _}, 1000
      GenServer.stop(pid)
    end

    test "explicit transport: :local also goes through Server.start_link" do
      {:ok, pid} =
        SupervisedApp.start_link(
          name: nil,
          transport: :local,
          test_pid: self(),
          test_mode: {40, 10}
        )

      assert_receive {:supervised_mounted, _}, 1000
      GenServer.stop(pid)
    end

    test "dispatch_start/1 routes :local to ExRatatui.Server" do
      {:ok, pid} =
        ExRatatui.App.dispatch_start(
          mod: SupervisedApp,
          name: nil,
          transport: :local,
          test_pid: self(),
          test_mode: {40, 10}
        )

      assert_receive {:supervised_mounted, _}, 1000
      GenServer.stop(pid)
    end

    test "dispatch_start/1 routes :ssh to ExRatatui.SSH.Daemon" do
      # The dispatch shim is transport-only wiring; we don't want this
      # test to stand up a real `:ssh.daemon/2`. The `:daemon_starter`
      # injection point makes the wiring observable without any OTP
      # sockets: if the fake starter fires with our mod, we know the
      # shim did its job.
      parent = self()

      fake_starter = fn port, _opts ->
        send(parent, {:fake_started, port})
        {:ok, :fake_daemon_ref}
      end

      fake_stopper = fn _ref -> :ok end

      {:ok, pid} =
        ExRatatui.App.dispatch_start(
          mod: SupervisedApp,
          transport: :ssh,
          name: nil,
          port: 0,
          daemon_starter: fake_starter,
          daemon_stopper: fake_stopper
        )

      assert_receive {:fake_started, 0}, 1000
      GenServer.stop(pid)
    end

    test "dispatch_start/1 routes :distributed to ExRatatui.Distributed.Listener" do
      {:ok, pid} =
        ExRatatui.App.dispatch_start(
          mod: SupervisedApp,
          transport: :distributed,
          name: nil
        )

      # The returned pid is a Supervisor (Listener), not a GenServer
      assert Process.alive?(pid)

      # It should have a DynamicSupervisor child for sessions
      children = Supervisor.which_children(pid)
      assert length(children) == 1
      assert {_id, _sup_pid, :supervisor, _} = hd(children)

      Supervisor.stop(pid)
    end
  end

  # -- A module with no `use`, the shape Erlang and Gleam modules have --

  defmodule PlainApp do
    @behaviour ExRatatui.App

    @impl true
    def mount(opts) do
      state = %{test_pid: Keyword.fetch!(opts, :test_pid), count: 0, ticks: 0}
      {:ok, state, commands: [Command.message(:boot)]}
    end

    @impl true
    def render(state, frame) do
      rect = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}
      [{%Paragraph{text: "count: #{state.count}"}, rect}]
    end

    @impl true
    def handle_event(%Key{code: "up"}, state), do: {:noreply, %{state | count: state.count + 1}}
    def handle_event(%Key{code: "q"}, state), do: {:stop, state}
    def handle_event(_event, state), do: {:noreply, state}

    @impl true
    def handle_info(:boot, state) do
      send(state.test_pid, :boot_handled)
      {:noreply, state}
    end

    def handle_info(:tick, state) do
      send(state.test_pid, {:ticked, state.ticks + 1})
      {:noreply, %{state | ticks: state.ticks + 1}, render?: false}
    end

    @impl true
    def subscriptions(%{ticks: ticks}) when ticks < 2 do
      [Subscription.interval(:ticker, 10, :tick)]
    end

    def subscriptions(_state), do: []
  end

  defmodule MinimalPlainApp do
    @behaviour ExRatatui.App

    @impl true
    def mount(_opts), do: {:ok, :state}

    @impl true
    def render(_state, _frame), do: []

    @impl true
    def handle_event(_event, state), do: {:noreply, state}
  end

  defp start_plain_app(opts \\ []) do
    App.start_link(PlainApp, [name: nil, test_pid: self(), test_mode: {40, 5}] ++ opts)
  end

  defp key(code), do: %Key{code: code, kind: "press"}

  defp buffer(pid) do
    %{terminal_ref: terminal_ref} = :sys.get_state(pid)
    ExRatatui.get_buffer_content(terminal_ref)
  end

  describe "start_link/2 with a plain module" do
    test "mounts, renders, and handles events" do
      {:ok, pid} = start_plain_app()
      assert buffer(pid) =~ "count: 0"

      assert :ok = Runtime.inject_event(pid, key("up"))
      assert :ok = Runtime.inject_event(pid, key("up"))
      assert buffer(pid) =~ "count: 2"

      assert %{mode: :callbacks, mod: PlainApp} = Runtime.snapshot(pid)
      GenServer.stop(pid)
    end

    test "delivers commands to handle_info/2" do
      {:ok, pid} = start_plain_app()
      assert_receive :boot_handled, 1000
      GenServer.stop(pid)
    end

    test "runs subscriptions and honours render?: false" do
      {:ok, pid} = start_plain_app()
      assert_receive {:ticked, 1}, 1000
      assert_receive {:ticked, 2}, 1000
      refute_receive {:ticked, 3}, 50

      # A sync call so the second tick's transition has finished.
      assert %{subscription_count: 0, render_count: render_count} = Runtime.snapshot(pid)

      # The mount and :boot transitions can draw, the ticks must not.
      assert render_count <= 2
      GenServer.stop(pid)
    end

    test "stops when a callback returns {:stop, state}" do
      {:ok, pid} = start_plain_app()
      ref = Process.monitor(pid)

      Runtime.inject_event(pid, key("q"))

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "falls back to the defaults for missing optional callbacks" do
      {:ok, pid} = App.start_link(MinimalPlainApp, name: nil, test_mode: {40, 5})
      ref = Process.monitor(pid)

      send(pid, :ignored)

      assert %{mode: :callbacks, subscription_count: 0} = Runtime.snapshot(pid)
      GenServer.stop(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "routes transport: :ssh to ExRatatui.SSH.Daemon" do
      parent = self()

      {:ok, pid} =
        App.start_link(PlainApp,
          transport: :ssh,
          name: nil,
          port: 0,
          daemon_starter: fn port, _opts ->
            send(parent, {:fake_started, port})
            {:ok, :fake_daemon_ref}
          end,
          daemon_stopper: fn _ref -> :ok end
        )

      assert_receive {:fake_started, 0}, 1000
      GenServer.stop(pid)
    end

    test "routes transport: :distributed to ExRatatui.Distributed.Listener" do
      {:ok, pid} = App.start_link(PlainApp, transport: :distributed, name: nil)

      assert [{_id, _sup_pid, :supervisor, _}] = Supervisor.which_children(pid)
      Supervisor.stop(pid)
    end

    test "rejects a module that is not an atom" do
      assert_raise FunctionClauseError, fn -> App.start_link(untyped("not_a_module")) end
    end

    test "rejects opts that are not a list" do
      assert_raise FunctionClauseError, fn -> App.start_link(PlainApp, untyped(:not_a_list)) end
    end
  end

  describe "child_spec/2" do
    test "matches what use generates, apart from the start function" do
      generated = SupervisedApp.child_spec(name: nil)
      spec = App.child_spec(SupervisedApp, name: nil)

      assert Map.delete(spec, :start) == Map.delete(generated, :start)
      assert spec.start == {App, :start_link, [SupervisedApp, [name: nil]]}
    end

    test "defaults to no options" do
      assert App.child_spec(PlainApp).start == {App, :start_link, [PlainApp, []]}
    end

    test "starts a plain module under a supervisor" do
      opts = [name: nil, test_pid: self(), test_mode: {40, 5}]

      {:ok, sup} =
        Supervisor.start_link([App.child_spec(PlainApp, opts)], strategy: :one_for_one)

      assert_receive :boot_handled, 1000
      assert [{PlainApp, pid, :worker, _}] = Supervisor.which_children(sup)
      assert %{mod: PlainApp} = Runtime.snapshot(pid)

      Supervisor.stop(sup)
    end

    test "rejects a module that is not an atom" do
      assert_raise FunctionClauseError, fn -> App.child_spec(untyped("not_a_module")) end
    end
  end
end
