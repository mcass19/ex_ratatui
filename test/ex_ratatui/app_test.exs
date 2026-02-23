defmodule ExRatatui.AppTest do
  use ExUnit.Case, async: true

  defmodule SampleApp do
    use ExRatatui.App

    @impl true
    def mount(_opts), do: {:ok, %{count: 0}}

    @impl true
    def render(state, _frame), do: [{:widget, state}]

    @impl true
    def handle_event(_event, state), do: {:noreply, state}
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
end
