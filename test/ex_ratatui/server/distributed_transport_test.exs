defmodule ExRatatui.Server.DistributedTransportTest do
  @moduledoc """
  Unit tests for `ExRatatui.Server` running under the
  `{:distributed_server, client_pid, width, height}` transport. These drive
  the Server directly with the test process standing in for the remote
  client — no real Erlang distribution or peer node is required.

  The end-to-end distributed path (peer node, `ExRatatui.Distributed.attach/3`,
  `ExRatatui.Distributed.Listener`) is covered by
  `ExRatatui.Distributed.IntegrationTest`.
  """

  use ExUnit.Case, async: true

  alias ExRatatui.Frame
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Runtime
  alias ExRatatui.Test.ServerApps.{Echo, FailingMount, StopOnAnyEvent}
  alias ExRatatui.Widgets.Paragraph

  defmodule DistReducerApp do
    use ExRatatui.App, runtime: :reducer

    alias ExRatatui.{Command, Subscription}

    @impl true
    def init(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:reducer_mounted, opts})
      {:ok, %{test_pid: test_pid, events: []}, commands: [Command.message(:boot)]}
    end

    @impl true
    def render(state, frame) do
      ordered_events = Enum.reverse(state.events)
      send(state.test_pid, {:reducer_rendered, ordered_events, frame})

      [
        {%Paragraph{text: inspect(ordered_events)},
         %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}
      ]
    end

    @impl true
    def update({:info, :boot}, state) do
      send(state.test_pid, :boot_seen)
      {:noreply, %{state | events: [:boot | state.events]}}
    end

    def update({:info, :tick}, state) do
      send(state.test_pid, :tick_seen)
      {:noreply, %{state | events: [:tick | state.events]}}
    end

    def update({:event, %ExRatatui.Event.Key{} = event}, state) do
      send(state.test_pid, {:reducer_event, event})
      {:noreply, %{state | events: [{:event, event.code} | state.events]}}
    end

    def update(_msg, state), do: {:noreply, state}

    @impl true
    def subscriptions(%{events: events}) do
      if Enum.member?(events, :boot) and not Enum.member?(events, :tick) do
        [Subscription.once(:after_boot, 10, :tick)]
      else
        []
      end
    end
  end

  # An Echo variant that renders a TextInput + Textarea so the "stateful
  # widgets are snapshot before distribution" test can verify the server
  # snapshots NIF references into plain tuples.
  # 67-byte smallest-valid PNG used by the stateful-widgets snapshot test
  # so an Image alongside TextInput/Textarea also exercises the snapshot
  # path in Server.snapshot_stateful_widgets.
  @valid_png Base.decode64!(
               "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
             )

  defmodule DistStatefulApp do
    use ExRatatui.App

    @impl true
    def mount(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      png = Keyword.fetch!(opts, :valid_png)
      ti_state = ExRatatui.text_input_new()
      ExRatatui.text_input_set_value(ti_state, "hello")
      ta_state = ExRatatui.textarea_new()
      ExRatatui.textarea_set_value(ta_state, "line1\nline2")
      {:ok, image} = ExRatatui.Image.new(png, protocol: :halfblocks, resize: :fit)
      send(test_pid, {:mounted, opts})
      {:ok, %{test_pid: test_pid, ti: ti_state, ta: ta_state, image: image}}
    end

    @impl true
    def render(state, frame) do
      send(state.test_pid, :rendered)

      [
        {%ExRatatui.Widgets.TextInput{state: state.ti},
         %Rect{x: 0, y: 0, width: frame.width, height: 1}},
        {%ExRatatui.Widgets.Textarea{state: state.ta},
         %Rect{x: 0, y: 1, width: frame.width, height: frame.height - 2}},
        {state.image, %Rect{x: 0, y: frame.height - 1, width: frame.width, height: 1}}
      ]
    end

    @impl true
    def handle_event(_event, state), do: {:noreply, state}
  end

  describe "lifecycle" do
    test "start_link with {:distributed_server, ...} mounts and sends widgets to client" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:distributed_server, self(), 80, 24}
        )

      # mount sees augmented opts
      assert_receive {:mounted, opts}, 1000
      assert opts[:transport] == :distributed
      assert opts[:width] == 80
      assert opts[:height] == 24

      # initial render sends widgets as BEAM terms to client_pid
      assert_receive {:rendered, 0, %Frame{width: 80, height: 24}}, 1000
      assert_receive {:ex_ratatui_draw, widgets}, 1000
      assert [{%Paragraph{text: "count: 0"}, %Rect{}}] = widgets

      GenServer.stop(pid)
      assert_receive {:terminated, :normal}, 1000
    end

    test "mount returning {:error, _} stops the server" do
      Process.flag(:trap_exit, true)

      assert {:error, :mount_failed} =
               ExRatatui.Server.start_link(
                 mod: FailingMount,
                 name: nil,
                 transport: {:distributed_server, self(), 40, 10}
               )
    end

    test "server stops when client process exits" do
      # Spawn a fake client that we can kill
      client = spawn(fn -> Process.sleep(:infinity) end)

      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:distributed_server, client, 40, 10}
        )

      assert_receive {:mounted, _}, 1000
      ref = Process.monitor(pid)

      Process.exit(client, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
      assert_receive {:terminated, :normal}, 1000
    end

    test "terminate calls user terminate/2 callback" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:distributed_server, self(), 40, 10}
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:rendered, 0, _}, 1000
      assert_receive {:ex_ratatui_draw, _}, 1000

      ref = Process.monitor(pid)
      GenServer.stop(pid)

      assert_receive {:terminated, :normal}, 1000
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end

  describe "message handling" do
    test "{:ex_ratatui_event, event} drives handle_event and re-renders" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:distributed_server, self(), 40, 10}
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:rendered, 0, _}, 1000
      assert_receive {:ex_ratatui_draw, _initial}, 1000

      event = %ExRatatui.Event.Key{code: "x", modifiers: [], kind: "press"}
      send(pid, {:ex_ratatui_event, event})

      assert_receive {:event, ^event}, 1000
      assert_receive {:rendered, 1, _}, 1000

      # Second draw contains updated widget text
      assert_receive {:ex_ratatui_draw, widgets}, 1000
      assert [{%Paragraph{text: "count: 1"}, %Rect{}}] = widgets

      GenServer.stop(pid)
    end

    test "{:ex_ratatui_event, event} returning :stop shuts down cleanly" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: StopOnAnyEvent,
          name: nil,
          test_pid: self(),
          transport: {:distributed_server, self(), 40, 10}
        )

      ref = Process.monitor(pid)

      send(
        pid,
        {:ex_ratatui_event, %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}}
      )

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "{:ex_ratatui_resize, w, h} delivers Resize event to App and re-renders with new size" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:distributed_server, self(), 40, 10}
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:rendered, 0, %Frame{width: 40, height: 10}}, 1000
      assert_receive {:ex_ratatui_draw, _}, 1000

      send(pid, {:ex_ratatui_resize, 120, 40})

      # The App sees a Resize event (Echo bumps count on every event)
      # and the follow-up render uses the new dims.
      assert_receive {:event, %ExRatatui.Event.Resize{width: 120, height: 40}}, 1000
      assert_receive {:rendered, 1, %Frame{width: 120, height: 40}}, 1000

      GenServer.stop(pid)
    end

    test ":poll messages are silently absorbed" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:distributed_server, self(), 40, 10}
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:rendered, 0, _}, 1000
      assert_receive {:ex_ratatui_draw, _}, 1000

      send(pid, :poll)
      refute_receive {:rendered, _, _}, 50
      refute_receive {:event, _}, 50

      GenServer.stop(pid)
    end

    test "handle_info forwards non-transport messages to app module" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: Echo,
          name: nil,
          test_pid: self(),
          transport: {:distributed_server, self(), 40, 10}
        )

      assert_receive {:mounted, _}, 1000
      assert_receive {:rendered, 0, _}, 1000
      assert_receive {:ex_ratatui_draw, _}, 1000

      send(pid, {:custom, "hello"})
      assert_receive {:info, {:custom, "hello"}}, 1000

      GenServer.stop(pid)
    end
  end

  describe "reducer support" do
    test "reducer apps run with commands, subscriptions, and events" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: DistReducerApp,
          name: nil,
          test_pid: self(),
          transport: {:distributed_server, self(), 40, 10}
        )

      assert_receive {:reducer_mounted, opts}, 1000
      assert opts[:transport] == :distributed
      assert opts[:width] == 40
      assert opts[:height] == 10

      assert_receive {:reducer_rendered, [], %Frame{width: 40, height: 10}}, 1000
      assert_receive {:ex_ratatui_draw, initial_widgets}, 1000

      assert [{%Paragraph{text: "[]"}, %Rect{x: 0, y: 0, width: 40, height: 10}}] =
               initial_widgets

      assert_receive :boot_seen, 1000
      assert_receive {:reducer_rendered, [:boot], %Frame{width: 40, height: 10}}, 1000
      assert_receive {:ex_ratatui_draw, boot_widgets}, 1000

      assert [{%Paragraph{text: "[:boot]"}, %Rect{x: 0, y: 0, width: 40, height: 10}}] =
               boot_widgets

      assert_receive :tick_seen, 1000
      assert_receive {:reducer_rendered, [:boot, :tick], %Frame{width: 40, height: 10}}, 1000

      assert_receive {:ex_ratatui_draw, tick_widgets}, 1000

      assert [{%Paragraph{text: "[:boot, :tick]"}, %Rect{x: 0, y: 0, width: 40, height: 10}}] =
               tick_widgets

      event = %ExRatatui.Event.Key{code: "x", modifiers: [], kind: "press"}
      send(pid, {:ex_ratatui_event, event})

      assert_receive {:reducer_event, ^event}, 1000

      assert_receive {:reducer_rendered, [:boot, :tick, {:event, "x"}],
                      %Frame{width: 40, height: 10}},
                     1000

      assert_receive {:ex_ratatui_draw, event_widgets}, 1000

      assert [
               {%Paragraph{text: "[:boot, :tick, {:event, \"x\"}]"},
                %Rect{x: 0, y: 0, width: 40, height: 10}}
             ] = event_widgets

      snapshot = Runtime.snapshot(pid)
      assert snapshot.mode == :reducer
      assert snapshot.transport == :distributed_server
      refute snapshot.polling_enabled?
      assert snapshot.subscription_count == 0
      assert snapshot.active_async_commands == 0

      GenServer.stop(pid)
    end
  end

  describe "helpers" do
    test "augment_distributed_mount_opts adds transport/width/height" do
      opts = [mod: Echo, test_pid: self(), foo: :bar]
      result = ExRatatui.Server.augment_distributed_mount_opts(opts, 100, 50)

      assert result[:mod] == Echo
      assert result[:test_pid] == self()
      assert result[:foo] == :bar
      assert result[:transport] == :distributed
      assert result[:width] == 100
      assert result[:height] == 50
    end

    test "stateful widgets are snapshot before distribution" do
      {:ok, pid} =
        ExRatatui.Server.start_link(
          mod: DistStatefulApp,
          name: nil,
          test_pid: self(),
          valid_png: @valid_png,
          transport: {:distributed_server, self(), 40, 10}
        )

      assert_receive {:mounted, _}, 1000
      assert_receive :rendered, 1000
      assert_receive {:ex_ratatui_draw, widgets}, 1000

      # Each stateful widget's `state` must be a plain tuple (snapshot),
      # never a NIF reference — references can't cross node boundaries.
      [
        {%ExRatatui.Widgets.TextInput{state: ti_state}, _},
        {%ExRatatui.Widgets.Textarea{state: ta_state}, _},
        {%ExRatatui.Widgets.Image{state: img_state}, _}
      ] =
        widgets

      assert is_tuple(img_state), "expected Image state to be a snapshot tuple"
      refute is_reference(img_state)
      assert {bytes, protocol, resize, background} = img_state
      assert is_binary(bytes)
      assert byte_size(bytes) == byte_size(@valid_png)
      assert protocol == :halfblocks
      assert resize == :fit
      assert background == nil

      assert is_tuple(ti_state), "expected TextInput state to be a snapshot tuple"
      refute is_reference(ti_state)
      assert {value, cursor, viewport_offset} = ti_state
      assert value == "hello"
      assert is_integer(cursor)
      assert is_integer(viewport_offset)

      assert is_tuple(ta_state), "expected Textarea state to be a snapshot tuple"
      refute is_reference(ta_state)
      assert {ta_value, ta_row, ta_col} = ta_state
      assert ta_value == "line1\nline2"
      assert is_integer(ta_row)
      assert is_integer(ta_col)

      GenServer.stop(pid)
    end
  end
end
