defmodule ExRatatui.SSHTest do
  use ExUnit.Case, async: true

  doctest ExRatatui.SSH, import: false

  alias ExRatatui.Session
  alias ExRatatui.SSH

  @enter_screen "\e[?1049h\e[?25l"
  @leave_screen "\e[?1049l\e[?25h\e[0m"
  @cpr_size_query "\e[s\e[9999;9999H\e[6n\e[u"

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
      assert state.rendering == false
    end

    test "defaults app_opts/sender/replier/starter when not given" do
      {:ok, state} = SSH.init(mod: SampleApp)
      assert state.app_opts == []
      assert state.sender == (&:ssh_connection.send/3)
      assert state.replier == (&:ssh_connection.reply_request/4)
      assert state.starter == (&ExRatatui.Server.start_link/1)
    end

    test "defaults subsystem_mode to false" do
      # Shell mode (via ssh_cli) is the default so plain `use
      # ExRatatui.App` callers who hand-start the handler don't
      # accidentally opt into subsystem semantics.
      {:ok, state} = SSH.init(mod: SampleApp)
      assert state.subsystem_mode == false
    end

    test "reads subsystem: true from init args" do
      {:ok, state} = SSH.init(mod: SampleApp, subsystem: true)
      assert state.subsystem_mode == true
    end

    test "defaults :image_protocol to nil and stores it when given" do
      {:ok, state} = SSH.init(mod: SampleApp)
      assert state.image_protocol == nil

      {:ok, with_hint} = SSH.init(mod: SampleApp, image_protocol: :kitty)
      assert with_hint.image_protocol == :kitty
    end

    test "defaults :image_font_size to nil and stores it when given" do
      {:ok, state} = SSH.init(mod: SampleApp)
      assert state.image_font_size == nil

      {:ok, with_size} = SSH.init(mod: SampleApp, image_font_size: {10, 20})
      assert with_size.image_font_size == {10, 20}
    end
  end

  describe "image_protocol applied to per-client session" do
    test "subsystem mode applies the configured hint to the new session" do
      starter = fake_starter(self(), {:ok, spawn(fn -> Process.sleep(:infinity) end)})

      state = build_state(subsystem: true, starter: starter, image_protocol: :kitty)
      assert {:ok, new_state} = SSH.handle_msg({:ssh_channel_up, 9, :conn}, state)

      # The hint should have made it through Session.set_image_protocol.
      # Re-setting the same hint round-trips :ok, which is the cheapest
      # observable signal that the Session accepted it earlier.
      assert :ok = Session.set_image_protocol(new_state.session, :kitty)
      cleanup(new_state)
    end

    test "shell-mode pty_req applies the configured hint to the new session" do
      state = build_state(image_protocol: :sixel)

      msg =
        {:ssh_cm, :conn, {:pty, 11, true, {~c"xterm", 80, 24, 640, 480, []}}}

      assert {:ok, new_state} = SSH.handle_ssh_msg(msg, state)
      assert :ok = Session.set_image_protocol(new_state.session, :sixel)
      cleanup(new_state)
    end

    test "subsystem mode also applies :image_font_size to the session" do
      starter = fake_starter(self(), {:ok, spawn(fn -> Process.sleep(:infinity) end)})

      state =
        build_state(
          subsystem: true,
          starter: starter,
          image_protocol: :kitty,
          image_font_size: {12, 24}
        )

      assert {:ok, new_state} = SSH.handle_msg({:ssh_channel_up, 9, :conn}, state)

      # Round-trip the same value as a smoke check that the session
      # accepted the earlier font_size set.
      assert :ok = Session.set_image_font_size(new_state.session, {12, 24})
      cleanup(new_state)
    end

    test "shell-mode pty_req applies :image_font_size to the new session" do
      state = build_state(image_protocol: :kitty, image_font_size: {9, 18})

      msg =
        {:ssh_cm, :conn, {:pty, 11, true, {~c"xterm", 80, 24, 640, 480, []}}}

      assert {:ok, new_state} = SSH.handle_ssh_msg(msg, state)
      assert :ok = Session.set_image_font_size(new_state.session, {9, 18})
      cleanup(new_state)
    end
  end

  describe "subsystem/1" do
    test "returns the shape nerves_ssh / :ssh.daemon wants" do
      assert {name, {ExRatatui.SSH, args}} = SSH.subsystem(SampleApp)
      assert name == ~c"Elixir.ExRatatui.SSHTest.SampleApp"
      assert args[:mod] == SampleApp
    end

    test "flags its args with `subsystem: true`" do
      # OTP consumes the {:subsystem, _} request internally when
      # dispatching via the :subsystems config, so the handler never
      # sees it. This flag is what tells the channel process it was
      # spawned that way (so it starts the server on channel_up instead
      # of waiting for a shell request).
      assert {_name, {ExRatatui.SSH, args}} = SSH.subsystem(SampleApp)
      assert args[:subsystem] == true
    end
  end

  describe "handle_msg :ssh_channel_up" do
    test "shell mode just records the channel id and connection" do
      # Shell-mode handlers wait for pty_req + shell_req before starting
      # anything — channel_up is just a bookkeeping beat.
      state = build_state()
      assert {:ok, updated} = SSH.handle_msg({:ssh_channel_up, 7, :fake_conn}, state)
      assert updated.channel_id == 7
      assert updated.conn == :fake_conn
      assert updated.session == nil
      assert updated.server_pid == nil
      assert updated.rendering == false
    end

    test "subsystem mode synthesizes an 80x24 session and starts the server" do
      # Subsystem mode can't wait for pty_req/shell_req because OTP
      # consumes the subsystem dispatch itself and only forwards
      # channel_up. The handler has to boot the server from that
      # trigger alone.
      test_pid = self()

      starter = fn opts ->
        send(test_pid, {:server_opts, opts})
        {:ok, spawn_server(opts)}
      end

      state = build_state(subsystem: true, starter: starter)

      assert {:ok, new_state} = SSH.handle_msg({:ssh_channel_up, 9, :conn}, state)

      assert %Session{} = new_state.session
      assert Session.size(new_state.session) == {80, 24}
      assert new_state.conn == :conn
      assert new_state.channel_id == 9
      assert is_pid(new_state.server_pid)
      assert new_state.rendering == true

      assert_receive {:server_opts, _}
      # enter_screen is queued before the server starts so the client's
      # terminal switches to the alt buffer before the first frame.
      assert_receive {:sent, :conn, 9, @enter_screen}
      # CPR roundtrip fires right after the server boots so the client
      # reports its real pty size — OTP consumed pty_req before our
      # handler existed, so this is the only way to learn the actual
      # dimensions in subsystem mode.
      assert_receive {:sent, :conn, 9, @cpr_size_query}

      cleanup(new_state)
    end

    test "subsystem mode closes the session and stops on starter failure" do
      state = build_state(subsystem: true, starter: fn _ -> {:error, :nope} end)

      assert {:stop, 9, _} = SSH.handle_msg({:ssh_channel_up, 9, :conn}, state)
      # start_server/1 emits both the prelude and the cleanup so a
      # briefly connected client doesn't get stranded in the alt buffer.
      assert_receive {:sent, :conn, 9, @enter_screen}
      assert_receive {:sent, :conn, 9, @leave_screen}
    end
  end

  describe "handle_msg :EXIT from server" do
    test "stops the channel when the linked server dies" do
      server_pid = spawn(fn -> :ok end)
      state = build_state() |> Map.merge(%{server_pid: server_pid, channel_id: 3})

      assert {:stop, 3, new_state} = SSH.handle_msg({:EXIT, server_pid, :shutdown}, state)
      assert new_state.server_pid == nil
    end

    test "flushes leave-screen bytes while the channel is still writable" do
      # Regression: the leave sequence must be emitted from handle_msg,
      # not from terminate/2. By the time ssh_server_channel gets around
      # to calling terminate the channel has already been closed from
      # under us, so any sender call there is a silent no-op and the
      # client gets stranded in the alt buffer with the cursor hidden.
      server_pid = spawn(fn -> :ok end)

      state =
        build_state()
        |> Map.merge(%{
          server_pid: server_pid,
          channel_id: 3,
          conn: :conn,
          rendering: true
        })

      assert {:stop, 3, new_state} = SSH.handle_msg({:EXIT, server_pid, :normal}, state)
      assert_receive {:sent, :conn, 3, @leave_screen}
      # rendering flipped off so terminate/2 won't double-send.
      assert new_state.rendering == false
    end

    test "does not emit leave-screen when rendering never started" do
      server_pid = spawn(fn -> :ok end)

      state =
        build_state()
        |> Map.merge(%{
          server_pid: server_pid,
          channel_id: 3,
          conn: :conn,
          rendering: false
        })

      assert {:stop, 3, _} = SSH.handle_msg({:EXIT, server_pid, :normal}, state)
      refute_receive {:sent, :conn, 3, @leave_screen}
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

    test "resizes the existing session in place when one already exists" do
      # Simulates the `ssh -t -s Elixir.MyApp.TUI` flow: subsystem mode
      # already spun up an 80x24 session + server at channel_up, and now
      # the client's pty_req arrives with the real dimensions. The
      # handler must resize in place (same session reference) — swapping
      # the struct would leave the server rendering into a Session the
      # channel no longer points at.
      {:ok, server} = __MODULE__.FakeServer.start_link()

      existing = Session.new(80, 24)

      state = %{
        build_state()
        | session: existing,
          server_pid: server,
          channel_id: 7,
          conn: :conn_ref,
          rendering: true
      }

      pty_msg =
        {:ssh_cm, :conn_ref, {:pty, 7, true, {~c"xterm", 120, 40, 0, 0, []}}}

      assert {:ok, new_state} = SSH.handle_ssh_msg(pty_msg, state)

      # Same Session struct — not a new one.
      assert new_state.session === existing
      assert Session.size(existing) == {120, 40}
      assert new_state.server_pid == server

      assert_receive {:replied, :conn_ref, true, :success, 7}
      assert_receive {:server_got, {:ex_ratatui_resize, 120, 40}}

      Session.close(existing)
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
      assert new_state.rendering == true
      assert_receive {:replied, :conn, true, :success, _}
      assert_receive {:sent, :conn, _, @enter_screen}

      cleanup(new_state)
    end

    test "with a failing starter replies failure and stops" do
      state =
        build_state(starter: fn _opts -> {:error, :boom} end)
        |> prime_with_pty(80, 24)

      shell_msg = {:ssh_cm, :conn, {:shell, state.channel_id, true}}
      assert {:stop, _id, new_state} = SSH.handle_ssh_msg(shell_msg, state)
      # rendering stays false on failure so terminate/2 won't try to
      # emit a second leave-screen (start_server already did).
      assert new_state.rendering == false
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

    test "a Cursor Position Report response resizes the session in place" do
      # Regression: subsystem mode can't read pty_req off the wire
      # because OTP consumes it before the subsystem handler takes over
      # the channel. Instead, channel_up fires an `ESC[6n` CPR query,
      # the client answers with `ESC[<row>;<col>R` on the next
      # `{:data, ...}` message, and the session's ANSI parser decodes
      # it into a `%Event.Resize{}`. The data handler must intercept
      # that Resize event and do the same dance as `{:window_change,
      # ...}` — resize the existing session in place + notify the
      # server via `{:ex_ratatui_resize, w, h}` — instead of forwarding
      # it as a plain `{:ex_ratatui_event, ...}` message.
      {:ok, server} = __MODULE__.FakeServer.start_link()
      session = Session.new(80, 24)

      state =
        build_state(subsystem: true)
        |> Map.merge(%{
          session: session,
          server_pid: server,
          channel_id: 5,
          conn: :conn,
          rendering: true
        })

      # `ESC[40;120R` = row 40, col 120, so the session should end up
      # at width=120, height=40.
      data_msg = {:ssh_cm, :conn, {:data, 5, 0, "\e[40;120R"}}
      assert {:ok, ^state} = SSH.handle_ssh_msg(data_msg, state)

      assert Session.size(session) == {120, 40}
      assert_receive {:server_got, {:ex_ratatui_resize, 120, 40}}
      # CPR responses must never reach the server as a plain input
      # event — the Server would treat it as a synthetic resize event
      # and double-route the dimensions through render state.
      refute_receive {:server_got, {:ex_ratatui_event, _}}

      Session.close(session)
      GenServer.stop(server)
    end
  end

  describe "bare Esc detection" do
    test "a bare 0x1B with no follow-up schedules the esc timer" do
      {:ok, server} = __MODULE__.FakeServer.start_link()
      session = Session.new(80, 24)

      state =
        build_state()
        |> Map.merge(%{
          session: session,
          server_pid: server,
          channel_id: 5,
          conn: :conn
        })

      # Feed a lone ESC byte — the VTE parser buffers it (no events).
      data_msg = {:ssh_cm, :conn, {:data, 5, 0, <<0x1B>>}}
      assert {:ok, new_state} = SSH.handle_ssh_msg(data_msg, state)

      assert is_reference(new_state.esc_timer)
      # No events dispatched yet — the timer hasn't fired.
      refute_receive {:server_got, {:ex_ratatui_event, _}}

      Session.close(session)
      GenServer.stop(server)
    end

    test "esc_timeout fires a synthetic Esc press and resets the parser" do
      {:ok, server} = __MODULE__.FakeServer.start_link()
      session = Session.new(80, 24)

      # Put the parser in the Escape state by feeding a bare 0x1B.
      [] = Session.feed_input(session, <<0x1B>>)

      state =
        build_state()
        |> Map.merge(%{
          session: session,
          server_pid: server,
          channel_id: 5,
          conn: :conn,
          esc_timer: make_ref()
        })

      assert {:ok, new_state} = SSH.handle_msg(:esc_timeout, state)
      assert new_state.esc_timer == nil

      assert_receive {:server_got,
                      {:ex_ratatui_event,
                       %ExRatatui.Event.Key{code: "esc", modifiers: [], kind: "press"}}}

      # The parser was reset — the next byte is parsed from Ground,
      # not as a continuation of the old escape sequence.
      [%ExRatatui.Event.Key{code: "a"}] = Session.feed_input(session, "a")

      Session.close(session)
      GenServer.stop(server)
    end

    test "esc_timeout without active session/server just clears the timer" do
      state = build_state() |> Map.merge(%{esc_timer: make_ref()})

      assert {:ok, new_state} = SSH.handle_msg(:esc_timeout, state)
      assert new_state.esc_timer == nil
    end

    test "follow-up data flushes an already-delivered esc_timeout from the mailbox" do
      {:ok, server} = __MODULE__.FakeServer.start_link()
      session = Session.new(80, 24)

      # Use a 0 ms timer so it fires immediately and lands in the
      # mailbox before the next handle_ssh_msg call.
      timer_ref = Process.send_after(self(), :esc_timeout, 0)
      # Give the timer time to deliver.
      Process.sleep(5)

      state =
        build_state()
        |> Map.merge(%{
          session: session,
          server_pid: server,
          channel_id: 5,
          conn: :conn,
          esc_timer: timer_ref
        })

      # Feed a regular keystroke — cancel_esc_timer must flush the
      # already-delivered :esc_timeout from the mailbox.
      data_msg = {:ssh_cm, :conn, {:data, 5, 0, "x"}}
      assert {:ok, new_state} = SSH.handle_ssh_msg(data_msg, state)

      assert new_state.esc_timer == nil
      # The stale :esc_timeout was consumed inside cancel_esc_timer,
      # not left dangling in the mailbox.
      refute_receive :esc_timeout

      Session.close(session)
      GenServer.stop(server)
    end

    test "follow-up data cancels a pending esc timer" do
      {:ok, server} = __MODULE__.FakeServer.start_link()
      session = Session.new(80, 24)

      # Simulate: bare ESC was fed, timer is pending.
      [] = Session.feed_input(session, <<0x1B>>)
      timer_ref = Process.send_after(self(), :esc_timeout, 60_000)

      state =
        build_state()
        |> Map.merge(%{
          session: session,
          server_pid: server,
          channel_id: 5,
          conn: :conn,
          esc_timer: timer_ref
        })

      # Feed "[A" — completes the CSI Up arrow sequence.
      data_msg = {:ssh_cm, :conn, {:data, 5, 0, "[A"}}
      assert {:ok, new_state} = SSH.handle_ssh_msg(data_msg, state)

      # Timer was cancelled.
      assert new_state.esc_timer == nil
      # The Up arrow event was dispatched.
      assert_receive {:server_got,
                      {:ex_ratatui_event,
                       %ExRatatui.Event.Key{code: "up", modifiers: [], kind: "press"}}}

      # No stale esc_timeout arrives.
      refute_receive :esc_timeout

      Session.close(session)
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

    test "emits the leave-screen sequence when rendering started" do
      state =
        build_state()
        |> Map.merge(%{
          rendering: true,
          conn: :conn,
          channel_id: 11,
          session: nil,
          server_pid: nil
        })

      assert :ok = SSH.terminate(:normal, state)
      assert_receive {:sent, :conn, 11, @leave_screen}
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
      assert {:session, _, writer_fn} = opts[:transport]
      assert is_function(writer_fn, 1)

      # enter_screen is queued on the channel before the starter runs
      # so the client's terminal switches to the alt buffer before any
      # render frames arrive.
      assert_receive {:sent, :conn, _, @enter_screen}

      Session.close(state.session)
    end

    test "emits leave-screen bytes when the starter fails" do
      state =
        build_state(starter: fn _opts -> {:error, :boom} end)
        |> prime_with_pty(80, 24)

      assert {:error, :boom} = SSH.start_server(state)

      # Both prelude and cleanup must reach the client so a briefly
      # connected session doesn't leave the client stuck on an empty
      # alt buffer.
      assert_receive {:sent, :conn, _, @enter_screen}
      assert_receive {:sent, :conn, _, @leave_screen}

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
