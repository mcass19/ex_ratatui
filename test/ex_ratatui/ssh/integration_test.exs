defmodule ExRatatui.SSH.IntegrationTest do
  @moduledoc """
  End-to-end smoke test against a real OTP `:ssh` daemon + client pair.

  Unlike the unit tests in `ExRatatui.SSHTest` and `ExRatatui.SSH.DaemonTest`
  — which replace `:ssh_connection.*` with fakes — this test stands up a
  live `:ssh.daemon/2`, connects to it with `:ssh.connect/3`, opens a
  real PTY session channel, and asserts that:

    * `mount/1` fires on the server side,
    * render bytes flow out to the client over the channel,
    * keyboard input flows back in and reaches `handle_event/2`,
    * the channel shuts down cleanly when we close the connection.

  We generate a throwaway RSA host key per test into `tmp_dir` so we
  don't depend on any host-wide ssh config, and we listen on port 0 so
  the test can run in parallel with anything else.
  """

  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag capture_log: true

  alias ExRatatui.SSH.Daemon

  defmodule DemoApp do
    @moduledoc false
    use ExRatatui.App

    alias ExRatatui.Widgets.Paragraph
    alias ExRatatui.Layout.Rect

    @impl true
    def mount(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      send(test_pid, {:mounted, self()})
      {:ok, %{test_pid: test_pid}}
    end

    @impl true
    def render(state, frame) do
      send(state.test_pid, :rendered)

      [
        {%Paragraph{text: "hello from ssh"},
         %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}
      ]
    end

    @impl true
    def handle_event(event, state) do
      send(state.test_pid, {:event, event})
      {:noreply, state}
    end
  end

  setup %{tmp_dir: tmp_dir} do
    system_dir = Path.join(tmp_dir, "system")
    user_dir = Path.join(tmp_dir, "user")
    File.mkdir_p!(system_dir)
    File.mkdir_p!(user_dir)
    generate_host_key!(system_dir)

    {:ok, system_dir: String.to_charlist(system_dir), user_dir: String.to_charlist(user_dir)}
  end

  test "round-trips a TUI session over a live :ssh daemon", ctx do
    {:ok, daemon_pid} =
      Daemon.start_link(
        mod: DemoApp,
        name: nil,
        port: 0,
        system_dir: ctx.system_dir,
        user_dir: ctx.system_dir,
        auth_methods: ~c"password",
        user_passwords: [{~c"alice", ~c"secret"}],
        app_opts: [test_pid: self()]
      )

    port = resolve_port(daemon_pid)
    assert is_integer(port) and port > 0

    {:ok, conn} =
      :ssh.connect(~c"127.0.0.1", port,
        user: ~c"alice",
        password: ~c"secret",
        silently_accept_hosts: true,
        user_dir: ctx.user_dir,
        user_interaction: false,
        auth_methods: ~c"password"
      )

    {:ok, chan} = :ssh_connection.session_channel(conn, :infinity)

    :success =
      :ssh_connection.ptty_alloc(conn, chan, term: ~c"xterm", width: 80, height: 24)

    :ok = :ssh_connection.shell(conn, chan)

    # Our DemoApp.mount/1 fires on the server side as soon as the
    # channel's linked ExRatatui.Server boots.
    assert_receive {:mounted, server_pid}, 2000
    assert is_pid(server_pid)

    # The server does an initial render in handle_continue, which flushes
    # bytes through the writer_fn → :ssh_connection.send back to us.
    assert_receive :rendered, 2000
    assert_receive {:ssh_cm, ^conn, {:data, ^chan, 0, bytes}}, 2000
    assert is_binary(bytes) or is_list(bytes)

    # Typing "a" at the client end should arrive at the server as a
    # parsed Key event.
    :ok = :ssh_connection.send(conn, chan, "a")
    assert_receive {:event, %ExRatatui.Event.Key{code: "a"}}, 2000

    # Resize on the client end should propagate all the way through the
    # pty → Session.resize → server handle_info.
    :ok = :ssh_connection.window_change(conn, chan, 120, 40)
    assert_receive :rendered, 2000

    :ok = :ssh.close(conn)
    GenServer.stop(daemon_pid)
  end

  ## Helpers

  defp resolve_port(daemon_pid) do
    {:ok, daemon_ref} = Daemon.daemon_ref(daemon_pid)
    {:ok, info} = :ssh.daemon_info(daemon_ref)
    Keyword.fetch!(info, :port)
  end

  defp generate_host_key!(system_dir) do
    # Generate a throwaway RSA host key in the PEM shape `:ssh` expects
    # when it scans `system_dir` for `ssh_host_rsa_key`.
    key = :public_key.generate_key({:rsa, 2048, 65_537})
    pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, key)
    pem = :public_key.pem_encode([pem_entry])
    File.write!(Path.join(system_dir, "ssh_host_rsa_key"), pem)
  end
end
