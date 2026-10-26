defmodule ExRatatui.IODeviceTest do
  use ExUnit.Case, async: true

  doctest ExRatatui.IODevice

  alias ExRatatui.Event
  alias ExRatatui.IODevice

  @enter_screen "\e[?1049h\e[?25l"
  @leave_screen "\e[?1049l\e[?25h\e[0m"

  # Forwards every event and frame size to the test; `q` stops, `!` crashes.
  defmodule KeyApp do
    use ExRatatui.App

    @impl true
    def mount(opts) do
      case Keyword.fetch!(opts, :test_pid) do
        :refuse ->
          {:error, :refused}

        test_pid ->
          send(test_pid, {:mounted, self()})
          {:ok, %{test_pid: test_pid}}
      end
    end

    @impl true
    def render(state, frame) do
      send(state.test_pid, {:frame, frame.width, frame.height})
      []
    end

    @impl true
    def handle_event(%Event.Key{code: "q"}, state), do: {:stop, state}
    def handle_event(%Event.Key{code: "!"}, _state), do: raise("boom")
    def handle_event(%Event.Key{code: "x"}, _state), do: exit({:shutdown, :bye})

    def handle_event(event, state) do
      send(state.test_pid, {:event, event})
      {:noreply, state}
    end
  end

  # Speaks enough of the Erlang I/O protocol to stand in for an SSH shell's
  # group leader: options, geometry, writes (forwarded to the test) and one
  # pending character read that `type/2` answers.
  defmodule FakeDevice do
    use GenServer

    def start(test_pid, opts \\ []), do: GenServer.start(__MODULE__, {test_pid, opts})

    def type(device, chars), do: send(device, {:type, chars})
    def resize(device, size), do: send(device, {:resize, size})
    def close(device), do: send(device, :close)

    @impl true
    def init({test_pid, opts}) do
      if driver = opts[:dictionary_driver], do: Process.put(:user_drv, driver)

      {:ok,
       %{
         test_pid: test_pid,
         size: Keyword.get(opts, :size, {100, 30}),
         driver: opts[:driver],
         reader: nil
       }}
    end

    @impl true
    def handle_info({:io_request, from, reply_as, request}, state) do
      case handle_request(request, {from, reply_as}, state) do
        {:reply, reply, state} ->
          send(from, {:io_reply, reply_as, reply})
          {:noreply, state}

        {:noreply, state} ->
          {:noreply, state}
      end
    end

    def handle_info({:type, chars}, %{reader: {from, reply_as}} = state) do
      send(from, {:io_reply, reply_as, chars})
      {:noreply, %{state | reader: nil}}
    end

    def handle_info({:resize, size}, state), do: {:noreply, %{state | size: size}}

    def handle_info(:close, %{reader: {from, reply_as}} = state) do
      send(from, {:io_reply, reply_as, :eof})
      {:noreply, %{state | reader: nil}}
    end

    def handle_info({:driver_id, reply_to}, %{driver: driver} = state) when is_pid(driver) do
      send(reply_to, {self(), :driver_id, driver})
      {:noreply, state}
    end

    def handle_info(_msg, state), do: {:noreply, state}

    defp handle_request(:getopts, _from, state), do: {:reply, [echo: true, binary: false], state}

    defp handle_request({:setopts, opts}, _from, state) do
      send(state.test_pid, {:setopts, opts})
      {:reply, :ok, state}
    end

    defp handle_request({:get_geometry, _axis}, _from, %{size: :unsupported} = state),
      do: {:reply, {:error, :enotsup}, state}

    defp handle_request({:get_geometry, :columns}, _from, %{size: {w, _}} = state),
      do: {:reply, w, state}

    defp handle_request({:get_geometry, :rows}, _from, %{size: {_, h}} = state),
      do: {:reply, h, state}

    defp handle_request({:put_chars, :unicode, chars}, _from, state) do
      send(state.test_pid, {:written, IO.iodata_to_binary(chars)})
      {:reply, :ok, state}
    end

    defp handle_request({:get_chars, :unicode, "", 1}, from, state),
      do: {:noreply, %{state | reader: from}}
  end

  defp start_device(opts \\ []) do
    {:ok, device} = FakeDevice.start(self(), opts)
    on_exit(fn -> Process.exit(device, :kill) end)
    device
  end

  defp run(device, opts \\ []) do
    opts = Keyword.merge([device: device, test_pid: self(), resize_interval_ms: 10], opts)
    Task.async(fn -> IODevice.run(KeyApp, opts) end)
  end

  # Typing before the bridge has asked for input would drop the keys.
  defp ready(device) do
    assert_receive {:frame, _w, _h}, 1000
    wait_for_reader(device)
  end

  defp wait_for_reader(device, attempts \\ 50) do
    case :sys.get_state(device).reader do
      nil when attempts > 0 ->
        Process.sleep(5)
        wait_for_reader(device, attempts - 1)

      _reader ->
        :ok
    end
  end

  describe "run/2" do
    test "draws on the device, reads keys from it, and gives it back on quit" do
      device = start_device()
      task = run(device)

      assert_receive {:setopts, [echo: false, binary: true]}
      assert_receive {:written, @enter_screen}
      assert_receive {:frame, 100, 30}, 1000
      wait_for_reader(device)

      FakeDevice.type(device, "a")
      assert_receive {:event, %Event.Key{code: "a", kind: "press"}}, 1000

      wait_for_reader(device)
      FakeDevice.type(device, "q")

      assert Task.await(task) == :ok
      assert_receive {:written, @leave_screen}
      assert_receive {:setopts, [echo: true, binary: false]}
    end

    test "decodes escape sequences split across reads" do
      device = start_device()
      task = run(device)
      ready(device)

      for char <- ["\e", "[", "A"] do
        wait_for_reader(device)
        FakeDevice.type(device, char)
      end

      assert_receive {:event, %Event.Key{code: "up"}}, 1000
      refute_receive {:event, %Event.Key{code: "esc"}}, 100

      wait_for_reader(device)
      FakeDevice.type(device, "q")
      assert Task.await(task) == :ok
    end

    test "a lone Esc arrives after the escape timeout" do
      device = start_device()
      task = run(device)
      ready(device)

      FakeDevice.type(device, "\e")
      assert_receive {:event, %Event.Key{code: "esc", kind: "press"}}, 1000

      wait_for_reader(device)
      FakeDevice.type(device, "q")
      assert Task.await(task) == :ok
    end

    test "follows the device's size" do
      device = start_device()
      task = run(device)
      ready(device)

      FakeDevice.resize(device, {120, 40})
      assert_receive {:event, %Event.Resize{width: 120, height: 40}}, 1000
      assert_receive {:frame, 120, 40}, 1000

      wait_for_reader(device)
      FakeDevice.type(device, "q")
      assert Task.await(task) == :ok
    end

    test "falls back to 80x24 when the device has no geometry" do
      device = start_device(size: :unsupported)
      task = run(device)

      assert_receive {:frame, 80, 24}, 1000
      # Let a few size polls come back unanswered; the size stays put.
      Process.sleep(50)
      refute_received {:event, %Event.Resize{}}
      wait_for_reader(device)

      FakeDevice.type(device, "q")
      assert Task.await(task) == :ok
    end

    test "asks for the kitty keyboard protocol inside the alternate screen" do
      device = start_device()
      task = run(device, keyboard_enhancement: true)

      assert_receive {:written, @enter_screen <> "\e[>15u"}
      ready(device)

      FakeDevice.type(device, "\e[1;1:3A")
      assert_receive {:event, %Event.Key{code: "up", kind: "release"}}, 1000

      wait_for_reader(device)
      FakeDevice.type(device, "q")
      assert Task.await(task) == :ok
      assert_receive {:written, "\e[<u" <> @leave_screen}
    end

    test "an app stopping with {:shutdown, _} is a normal return" do
      device = start_device()
      task = run(device)
      ready(device)

      FakeDevice.type(device, "x")
      assert Task.await(task) == :ok
    end

    test "ignores messages it doesn't know" do
      device = start_device()
      task = run(device)
      assert_receive {:mounted, server}
      ready(device)

      {:dictionary, dictionary} = Process.info(server, :dictionary)
      [bridge | _] = dictionary[:"$ancestors"]
      send(bridge, :unexpected)

      FakeDevice.type(device, "a")
      assert_receive {:event, %Event.Key{code: "a"}}, 1000

      wait_for_reader(device)
      FakeDevice.type(device, "q")
      assert Task.await(task) == :ok
    end

    test "new input drops an Esc timeout that already fired" do
      device = start_device()
      session = ExRatatui.Session.new(80, 24)
      timer = Process.send_after(self(), :esc_timeout, 0)
      Process.sleep(10)

      state = %IODevice{
        device: device,
        session: session,
        server_pid: self(),
        read_ref: make_ref(),
        size: {80, 24},
        esc_timer: timer
      }

      assert {:noreply, state} = IODevice.handle_info({:io_reply, state.read_ref, "a"}, state)
      assert state.esc_timer == nil
      assert_received {:ex_ratatui_event, %Event.Key{code: "a"}}
      refute_received :esc_timeout

      ExRatatui.Session.close(session)
    end

    test "returns when the shell closes" do
      device = start_device()
      task = run(device)
      ready(device)

      FakeDevice.close(device)
      assert Task.await(task) == :ok
      assert_receive {:written, @leave_screen}
    end

    test "returns when the device goes away" do
      device = start_device()
      task = run(device)
      ready(device)

      Process.exit(device, :kill)
      assert Task.await(task) == :ok
    end

    @tag capture_log: true
    test "passes an app crash on as an error, with the device restored" do
      device = start_device()
      task = run(device)
      ready(device)

      FakeDevice.type(device, "!")
      assert {:error, {%RuntimeError{message: "boom"}, _stack}} = Task.await(task)
      assert_receive {:written, @leave_screen}
      assert_receive {:setopts, [echo: true, binary: false]}
    end

    @tag capture_log: true
    test "an app that fails to mount leaves the device as it found it" do
      device = start_device()

      assert {:error, :refused} =
               IODevice.run(KeyApp, device: device, test_pid: :refuse)

      assert_receive {:written, @enter_screen}
      assert_receive {:written, @leave_screen}
      assert_receive {:setopts, [echo: true, binary: false]}
    end
  end

  describe "io_device?/1" do
    test "is true when the device's driver isn't this node's terminal" do
      driver = spawn(fn -> Process.sleep(:infinity) end)
      assert IODevice.io_device?(start_device(driver: driver))
    end

    test "falls back to the driver kept in the device's process dictionary" do
      driver = spawn(fn -> Process.sleep(:infinity) end)
      assert IODevice.io_device?(start_device(dictionary_driver: driver))
    end

    test "is false for a device that names no driver" do
      refute IODevice.io_device?(start_device())
    end

    test "asks the caller's group leader by default" do
      assert is_boolean(IODevice.io_device?())
    end

    test "is false for a device that has gone away" do
      device = start_device()
      Process.exit(device, :kill)
      refute IODevice.io_device?(device)
    end

    test "is false for an unregistered name" do
      refute IODevice.io_device?(:no_such_device)
    end

    test "is false for a device on a node we can't reach" do
      refute IODevice.io_device?(unreachable_pid())
    end
  end

  # A pid on a node that doesn't exist, built from the external term format.
  defp unreachable_pid do
    node = "nope@nohost"

    :erlang.binary_to_term(
      <<131, 88, 118, byte_size(node)::16, node::binary, 1::32, 0::32, 1::32>>
    )
  end
end
