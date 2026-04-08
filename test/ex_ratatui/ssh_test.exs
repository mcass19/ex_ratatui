defmodule ExRatatui.SSHTest do
  use ExUnit.Case, async: true

  doctest ExRatatui.SSH, import: false

  alias ExRatatui.SSH
  alias ExRatatui.Session

  defmodule SampleApp do
    use ExRatatui.App

    @impl true
    def mount(opts) do
      {:ok, %{test_pid: Keyword.fetch!(opts, :test_pid)}}
    end

    @impl true
    def render(_state, _frame), do: []

    @impl true
    def handle_event(_event, state), do: {:noreply, state}
  end

  defp fake_sender(test_pid) do
    fn conn, channel_id, bytes ->
      send(test_pid, {:sent, conn, channel_id, bytes})
      :ok
    end
  end

  defp fake_replier(test_pid) do
    fn conn, want_reply, status, channel_id ->
      send(test_pid, {:replied, conn, want_reply, status, channel_id})
      :ok
    end
  end

  defp fake_starter(test_pid, result) do
    fn opts ->
      send(test_pid, {:server_started, opts})
      result
    end
  end

  defp build_state(overrides \\ []) do
    base = [
      mod: SampleApp,
      app_opts: [],
      sender: fake_sender(self()),
      replier: fake_replier(self()),
      starter: fake_starter(self(), {:ok, spawn(fn -> Process.sleep(:infinity) end)})
    ]

    args = Keyword.merge(base, overrides)
    {:ok, state} = SSH.init(args)
    state
  end

  describe "init/1" do
    test "builds a state struct from the init args" do
      {:ok, state} =
        SSH.init(
          mod: SampleApp,
          app_opts: [foo: :bar],
          sender: fake_sender(self()),
          replier: fake_replier(self()),
          starter: fake_starter(self(), {:ok, self()})
        )

      assert state.mod == SampleApp
      assert state.app_opts == [foo: :bar]
      assert is_function(state.sender, 3)
      assert is_function(state.replier, 4)
      assert is_function(state.starter, 1)
      assert state.session == nil
      assert state.server_pid == nil
    end

    test "defaults app_opts/sender/replier/starter when not given" do
      {:ok, state} = SSH.init(mod: SampleApp)
      assert state.app_opts == []
      assert state.sender == (&:ssh_connection.send/3)
      assert state.replier == (&:ssh_connection.reply_request/4)
      assert state.starter == (&ExRatatui.Server.start_link/1)
    end
  end

  describe "subsystem/1" do
    test "returns the shape nerves_ssh / :ssh.daemon wants" do
      assert {name, {ExRatatui.SSH, args}} = SSH.subsystem(SampleApp)
      assert name == ~c"Elixir.ExRatatui.SSHTest.SampleApp"
      assert args[:mod] == SampleApp
    end
  end

  describe "handle_msg :ssh_channel_up" do
    test "records the channel id and connection" do
      state = build_state()
      assert {:ok, updated} = SSH.handle_msg({:ssh_channel_up, 7, :fake_conn}, state)
      assert updated.channel_id == 7
      assert updated.conn == :fake_conn
    end
  end

  describe "handle_msg :EXIT from server" do
    test "stops the channel when the linked server dies" do
      server_pid = spawn(fn -> :ok end)
      state = build_state() |> Map.merge(%{server_pid: server_pid, channel_id: 3})

      assert {:stop, 3, new_state} = SSH.handle_msg({:EXIT, server_pid, :shutdown}, state)
      assert new_state.server_pid == nil
    end

    test "ignores EXIT messages from other pids" do
      state = build_state() |> Map.merge(%{server_pid: self(), channel_id: 1})
      other = spawn(fn -> :ok end)
      assert {:ok, ^state} = SSH.handle_msg({:EXIT, other, :normal}, state)
    end

    test "ignores unrelated info messages" do
      state = build_state()
      assert {:ok, ^state} = SSH.handle_msg(:unrelated, state)
    end
  end

  describe "handle_ssh_msg :pty" do
    test "creates a session at the requested size and replies success" do
      state = build_state()

      pty_msg =
        {:ssh_cm, :conn_ref, {:pty, 2, true, {~c"xterm", 100, 30, 0, 0, []}}}

      assert {:ok, new_state} = SSH.handle_ssh_msg(pty_msg, state)
      assert_receive {:replied, :conn_ref, true, :success, 2}

      assert %Session{} = new_state.session
      assert Session.size(new_state.session) == {100, 30}
      assert new_state.channel_id == 2
      assert new_state.conn == :conn_ref

      Session.close(new_state.session)
    end

    test "clamps zero dimensions to the 80x24 fallback" do
      state = build_state()
      pty_msg = {:ssh_cm, :conn, {:pty, 1, false, {~c"xterm", 0, 0, 0, 0, []}}}

      assert {:ok, new_state} = SSH.handle_ssh_msg(pty_msg, state)
      assert Session.size(new_state.session) == {80, 24}
      Session.close(new_state.session)
    end
  end

  describe "handle_ssh_msg :shell" do
    test "without a pty replies failure and stops" do
      state = build_state()

      assert {:stop, 4, ^state} =
               SSH.handle_ssh_msg({:ssh_cm, :conn, {:shell, 4, true}}, state)

      assert_receive {:replied, :conn, true, :failure, 4}
    end

    test "with a pty launches the Server and replies success" do
      state =
        build_state(starter: fn opts -> {:ok, spawn_server(opts)} end)
        |> prime_with_pty(80, 24)

      shell_msg = {:ssh_cm, :conn, {:shell, state.channel_id, true}}

      assert {:ok, new_state} = SSH.handle_ssh_msg(shell_msg, state)
      assert is_pid(new_state.server_pid)
      assert_receive {:replied, :conn, true, :success, _}

      cleanup(new_state)
    end

    test "with a failing starter replies failure and stops" do
      state =
        build_state(starter: fn _opts -> {:error, :boom} end)
        |> prime_with_pty(80, 24)

      shell_msg = {:ssh_cm, :conn, {:shell, state.channel_id, true}}
      assert {:stop, _id, _state} = SSH.handle_ssh_msg(shell_msg, state)
      assert_receive {:replied, :conn, true, :failure, _}
      Session.close(state.session)
    end
  end

  describe "handle_ssh_msg :subsystem without a prior pty" do
    test "synthesizes an 80x24 session and starts the server" do
      test_pid = self()

      starter = fn opts ->
        send(test_pid, {:server_opts, opts})
        {:ok, spawn_server(opts)}
      end

      state = build_state(starter: starter)

      sub_msg = {:ssh_cm, :conn, {:subsystem, 9, true, ~c"Elixir.X"}}
      assert {:ok, new_state} = SSH.handle_ssh_msg(sub_msg, state)

      assert %Session{} = new_state.session
      assert Session.size(new_state.session) == {80, 24}
      assert new_state.conn == :conn
      assert new_state.channel_id == 9
      assert is_pid(new_state.server_pid)

      assert_receive {:replied, :conn, true, :success, 9}
      assert_receive {:server_opts, _}

      cleanup(new_state)
    end

    test "closes the synthesized session and stops on starter failure" do
      state = build_state(starter: fn _ -> {:error, :nope} end)
      sub_msg = {:ssh_cm, :conn, {:subsystem, 2, false, ~c"Elixir.X"}}

      assert {:stop, 2, _} = SSH.handle_ssh_msg(sub_msg, state)
      assert_receive {:replied, :conn, false, :failure, 2}
    end
  end

  describe "handle_ssh_msg :subsystem with an existing pty" do
    test "reuses the existing session and starts the server" do
      state =
        build_state(starter: fn opts -> {:ok, spawn_server(opts)} end)
        |> prime_with_pty(120, 40)

      sub_msg = {:ssh_cm, :conn, {:subsystem, state.channel_id, true, ~c"Elixir.X"}}

      assert {:ok, new_state} = SSH.handle_ssh_msg(sub_msg, state)
      # Session is the same instance
      assert new_state.session == state.session
      assert Session.size(new_state.session) == {120, 40}

      cleanup(new_state)
    end

    test "stops on starter failure with an existing pty" do
      state =
        build_state(starter: fn _opts -> {:error, :nope} end)
        |> prime_with_pty(100, 30)

      sub_msg = {:ssh_cm, :conn, {:subsystem, state.channel_id, true, ~c"Elixir.X"}}
      assert {:stop, _id, _state} = SSH.handle_ssh_msg(sub_msg, state)
      assert_receive {:replied, :conn, true, :failure, _}

      Session.close(state.session)
    end
  end

  describe "handle_ssh_msg :data" do
    test "feeds bytes to the session and forwards events to the server" do
      {:ok, server} = __MODULE__.FakeServer.start_link()

      state =
        build_state(starter: fn _opts -> {:ok, server} end)
        |> prime_with_pty(80, 24)

      state = %{state | server_pid: server}

      data_msg = {:ssh_cm, :conn, {:data, state.channel_id, 0, "a"}}
      assert {:ok, ^state} = SSH.handle_ssh_msg(data_msg, state)

      assert_receive {:server_got,
                      {:ex_ratatui_event,
                       %ExRatatui.Event.Key{code: "a", modifiers: [], kind: "press"}}}

      Session.close(state.session)
      GenServer.stop(server)
    end
  end

  describe "handle_ssh_msg :window_change" do
    test "resizes the session and forwards a resize message to the server" do
      {:ok, server} = __MODULE__.FakeServer.start_link()

      state =
        build_state(starter: fn _opts -> {:ok, server} end)
        |> prime_with_pty(80, 24)

      state = %{state | server_pid: server}

      win_msg = {:ssh_cm, :conn, {:window_change, state.channel_id, 200, 60, 0, 0}}
      assert {:ok, ^state} = SSH.handle_ssh_msg(win_msg, state)

      assert Session.size(state.session) == {200, 60}
      assert_receive {:server_got, {:ex_ratatui_resize, 200, 60}}

      Session.close(state.session)
      GenServer.stop(server)
    end
  end

  describe "handle_ssh_msg eof/exit/signal" do
    test ":eof stops the channel" do
      state = build_state() |> Map.put(:channel_id, 5)
      assert {:stop, 5, ^state} = SSH.handle_ssh_msg({:ssh_cm, :conn, {:eof, 5}}, state)
    end

    test ":exit_status stops the channel" do
      state = build_state() |> Map.put(:channel_id, 6)

      assert {:stop, 6, ^state} =
               SSH.handle_ssh_msg({:ssh_cm, :conn, {:exit_status, 6, 0}}, state)
    end

    test ":exit_signal stops the channel" do
      state = build_state() |> Map.put(:channel_id, 7)

      assert {:stop, 7, ^state} =
               SSH.handle_ssh_msg(
                 {:ssh_cm, :conn, {:exit_signal, 7, ~c"TERM", ~c"", ~c""}},
                 state
               )
    end

    test ":signal is ignored (RFC 4254 §6.9)" do
      state = build_state()
      assert {:ok, ^state} = SSH.handle_ssh_msg({:ssh_cm, :conn, {:signal, 1, ~c"HUP"}}, state)
    end

    test ":env replies failure and keeps the channel open" do
      state = build_state()

      assert {:ok, ^state} =
               SSH.handle_ssh_msg(
                 {:ssh_cm, :conn, {:env, 1, true, ~c"LANG", ~c"en_US.UTF-8"}},
                 state
               )

      assert_receive {:replied, :conn, true, :failure, 1}
    end

    test "unknown messages are ignored" do
      state = build_state()
      assert {:ok, ^state} = SSH.handle_ssh_msg({:ssh_cm, :conn, {:whatever, 1}}, state)
    end
  end

  describe "terminate/2" do
    test "closes the session and stops the server" do
      {:ok, server} = __MODULE__.FakeServer.start_link()
      # Unlink so the :shutdown exit doesn't propagate to the test proc.
      Process.unlink(server)
      ref = Process.monitor(server)

      state =
        build_state(starter: fn _opts -> {:ok, server} end)
        |> prime_with_pty(80, 24)

      state = %{state | server_pid: server}
      session = state.session

      assert :ok = SSH.terminate(:normal, state)
      assert_receive {:DOWN, ^ref, :process, ^server, :shutdown}, 1000

      # Session is closed — draws on it error.
      assert {:error, _} = Session.draw(session, [])
      refute Process.alive?(server)
    end

    test "is a no-op when there's no session or server" do
      state = build_state() |> Map.merge(%{session: nil, server_pid: nil})
      assert :ok = SSH.terminate(:normal, state)
    end

    test "skips dead servers without crashing" do
      dead = spawn(fn -> :ok end)
      ref = Process.monitor(dead)
      assert_receive {:DOWN, ^ref, :process, ^dead, _}, 1000

      state = build_state() |> Map.merge(%{server_pid: dead})
      assert :ok = SSH.terminate(:normal, state)
    end
  end

  describe "make_writer_fn/3" do
    @tag capture_log: true
    test "logs and swallows sender errors so render never crashes" do
      sender = fn _c, _ch, _b -> {:error, :closed} end
      writer = SSH.make_writer_fn(sender, :conn, 1)
      assert :ok = writer.("some bytes")
    end

    test "returns :ok on success" do
      sender = fn _c, _ch, _b -> :ok end
      writer = SSH.make_writer_fn(sender, :conn, 1)
      assert :ok = writer.("some bytes")
    end
  end

  describe "normalize_pty_size/2" do
    test "falls back to 80x24 for 0 dimensions" do
      assert SSH.normalize_pty_size(0, 0) == {80, 24}
    end

    test "passes positive integers through" do
      assert SSH.normalize_pty_size(100, 40) == {100, 40}
    end

    test "falls back when a dimension is not a positive integer" do
      assert SSH.normalize_pty_size(nil, 40) == {80, 40}
      assert SSH.normalize_pty_size(-5, 40) == {80, 40}
    end
  end

  describe "start_server/1" do
    test "calls the injected starter with transport opts" do
      test_pid = self()

      state =
        build_state(
          starter: fn opts ->
            send(test_pid, {:got_opts, opts})
            {:ok, self()}
          end
        )
        |> prime_with_pty(80, 24)

      {:ok, _} = SSH.start_server(state)

      assert_receive {:got_opts, opts}
      assert opts[:mod] == SampleApp
      assert opts[:name] == nil
      assert {:ssh, _, writer_fn} = opts[:transport]
      assert is_function(writer_fn, 1)

      Session.close(state.session)
    end
  end

  ## Helpers

  defp prime_with_pty(state, w, h) do
    msg = {:ssh_cm, :conn, {:pty, 1, false, {~c"xterm", w, h, 0, 0, []}}}
    {:ok, new_state} = SSH.handle_ssh_msg(msg, state)
    new_state
  end

  defp spawn_server(_opts) do
    spawn(fn -> Process.sleep(:infinity) end)
  end

  defp cleanup(state) do
    if state.server_pid && Process.alive?(state.server_pid) do
      Process.exit(state.server_pid, :kill)
    end

    if state.session do
      Session.close(state.session)
    end
  end

  defmodule FakeServer do
    use GenServer

    def start_link do
      GenServer.start_link(__MODULE__, self())
    end

    @impl true
    def init(test_pid), do: {:ok, test_pid}

    @impl true
    def handle_info(msg, test_pid) do
      send(test_pid, {:server_got, msg})
      {:noreply, test_pid}
    end
  end
end
