defmodule ExRatatui.SSH.DaemonTest do
  use ExUnit.Case, async: true

  alias ExRatatui.SSH.Daemon

  defmodule SampleApp do
    use ExRatatui.App

    @impl true
    def mount(_opts), do: {:ok, %{}}

    @impl true
    def render(_state, _frame), do: []

    @impl true
    def handle_event(_event, state), do: {:noreply, state}
  end

  defp fake_starter(test_pid, result \\ {:ok, :fake_ref}) do
    fn port, daemon_opts ->
      send(test_pid, {:fake_started, port, daemon_opts})
      result
    end
  end

  defp fake_stopper(test_pid) do
    fn ref ->
      send(test_pid, {:fake_stopped, ref})
      :ok
    end
  end

  defp temp_otp_app_fixture(tmp_dir) do
    unique = System.unique_integer([:positive])
    app = String.to_atom("ex_ratatui_daemon_test_app_#{unique}")
    mod = String.to_atom("Elixir.ExRatatui.SSH.DaemonTest.TempApp#{unique}")
    root = Path.join(tmp_dir, Atom.to_string(app))
    ebin = Path.join(root, "ebin")
    ssh_dir = Path.join(root, "priv/ssh")

    File.mkdir_p!(ebin)

    app_spec = {:application, app, [vsn: ~c"0.1.0", modules: [mod]]}
    app_file = Path.join(ebin, "#{app}.app")
    app_contents = :io_lib.format(~c"~tp.~n", [app_spec]) |> IO.iodata_to_binary()
    File.write!(app_file, app_contents)

    true = :code.add_pathz(String.to_charlist(ebin))

    Module.create(
      mod,
      quote do
        def ping, do: :pong
      end,
      Macro.Env.location(__ENV__)
    )

    :ok = Application.load(app)

    %{
      app: app,
      mod: mod,
      ebin: ebin,
      root: root,
      ssh_dir: ssh_dir
    }
  end

  describe "start_link/1" do
    test "starts the GenServer and invokes daemon_starter" do
      {:ok, pid} =
        Daemon.start_link(
          mod: SampleApp,
          name: nil,
          port: 0,
          daemon_starter: fake_starter(self()),
          daemon_stopper: fake_stopper(self())
        )

      assert_receive {:fake_started, 0, daemon_opts}, 1000
      assert Process.alive?(pid)

      # `:ssh.daemon/2` shape: both shell and subsystem routes point at
      # our channel module with the app mod baked in.
      assert {ExRatatui.SSH, cli_args} = daemon_opts[:ssh_cli]
      assert cli_args[:mod] == SampleApp
      assert [{_name, {ExRatatui.SSH, _}}] = daemon_opts[:subsystems]
      assert daemon_opts[:exec] == :disabled

      GenServer.stop(pid)
    end

    test "defaults :port to 2222 when not given" do
      {:ok, pid} =
        Daemon.start_link(
          mod: SampleApp,
          name: nil,
          daemon_starter: fake_starter(self()),
          daemon_stopper: fake_stopper(self())
        )

      assert_receive {:fake_started, 2222, _}, 1000
      GenServer.stop(pid)
    end

    test "supports a registered name" do
      {:ok, pid} =
        Daemon.start_link(
          mod: SampleApp,
          name: :ssh_daemon_named_test,
          port: 0,
          daemon_starter: fake_starter(self()),
          daemon_stopper: fake_stopper(self())
        )

      assert_receive {:fake_started, 0, _}, 1000
      assert Process.whereis(:ssh_daemon_named_test) == pid

      GenServer.stop(pid)
    end

    @tag capture_log: true
    test "stops with reason when daemon_starter returns {:error, _}" do
      Process.flag(:trap_exit, true)

      error_starter = fn _port, _opts -> {:error, :eaddrinuse} end

      assert {:error, {:ssh_daemon_failed, :eaddrinuse}} =
               Daemon.start_link(
                 mod: SampleApp,
                 name: nil,
                 port: 0,
                 daemon_starter: error_starter,
                 daemon_stopper: fake_stopper(self())
               )
    end
  end

  describe "daemon_ref/1 and port/1" do
    test "expose the underlying OTP daemon handle" do
      {:ok, pid} =
        Daemon.start_link(
          mod: SampleApp,
          name: nil,
          port: 4242,
          daemon_starter: fake_starter(self(), {:ok, :my_ref}),
          daemon_stopper: fake_stopper(self())
        )

      assert_receive {:fake_started, _, _}, 1000
      assert Daemon.daemon_ref(pid) == {:ok, :my_ref}
      assert Daemon.port(pid) == 4242

      GenServer.stop(pid)
    end

    test "default server arg resolves to __MODULE__" do
      # Covers the `\\ __MODULE__` default branch on both getters by
      # registering under the default name and calling them with no arg.
      {:ok, pid} =
        Daemon.start_link(
          mod: SampleApp,
          port: 5555,
          daemon_starter: fake_starter(self(), {:ok, :defaulted}),
          daemon_stopper: fake_stopper(self())
        )

      assert_receive {:fake_started, _, _}, 1000
      assert Daemon.daemon_ref() == {:ok, :defaulted}
      assert Daemon.port() == 5555

      GenServer.stop(pid)
    end
  end

  describe "terminate/2" do
    test "calls daemon_stopper with the stored daemon_ref" do
      {:ok, pid} =
        Daemon.start_link(
          mod: SampleApp,
          name: nil,
          port: 0,
          daemon_starter: fake_starter(self(), {:ok, :stop_me}),
          daemon_stopper: fake_stopper(self())
        )

      assert_receive {:fake_started, _, _}, 1000
      GenServer.stop(pid)

      assert_receive {:fake_stopped, :stop_me}, 1000
    end

    test "terminate/2 with no daemon_ref is a no-op" do
      state = %Daemon{
        mod: SampleApp,
        daemon_ref: nil,
        port: 0,
        daemon_stopper: fn _ -> flunk("should not be called") end
      }

      assert :ok = Daemon.terminate(:normal, state)
    end

    test "daemon_ref/1 returns {:error, :not_started} when ref is nil" do
      state = %Daemon{
        mod: SampleApp,
        daemon_ref: nil,
        port: 0,
        daemon_stopper: fn _ -> :ok end
      }

      assert {:reply, {:error, :not_started}, ^state} =
               Daemon.handle_call(:daemon_ref, self(), state)
    end
  end

  describe "build_daemon_opts/2" do
    test "strips infra keys and forwards the rest to :ssh.daemon/2" do
      opts = [
        mod: SampleApp,
        port: 9999,
        name: nil,
        daemon_starter: fn _, _ -> {:ok, :ref} end,
        daemon_stopper: fn _ -> :ok end,
        transport: :ssh,
        app_opts: [foo: :bar],
        system_dir: ~c"/etc/ssh",
        user_dir: ~c"/etc/users",
        authorized_keys: ~c"contents"
      ]

      daemon_opts = Daemon.build_daemon_opts(SampleApp, opts)

      # Infra keys are stripped
      refute Keyword.has_key?(daemon_opts, :mod)
      refute Keyword.has_key?(daemon_opts, :port)
      refute Keyword.has_key?(daemon_opts, :name)
      refute Keyword.has_key?(daemon_opts, :daemon_starter)
      refute Keyword.has_key?(daemon_opts, :daemon_stopper)
      refute Keyword.has_key?(daemon_opts, :transport)
      refute Keyword.has_key?(daemon_opts, :app_opts)

      # OTP keys are passed through verbatim
      assert daemon_opts[:system_dir] == ~c"/etc/ssh"
      assert daemon_opts[:user_dir] == ~c"/etc/users"
      assert daemon_opts[:authorized_keys] == ~c"contents"

      # Our channel wire-up is present. ssh_cli handles shell clients —
      # it waits for pty_req + shell_req, so it must NOT carry
      # `subsystem: true` (otherwise channel_up would race the pty).
      assert {ExRatatui.SSH, cli_args} = daemon_opts[:ssh_cli]
      assert cli_args[:mod] == SampleApp
      assert cli_args[:app_opts] == [foo: :bar]
      refute cli_args[:subsystem]
      assert daemon_opts[:exec] == :disabled

      # The :subsystems entry registers the same channel module under
      # the app module's full atom name. `subsystem: true` is what tells
      # the handler to kick off on channel_up instead of waiting for a
      # shell request (OTP consumes the {:subsystem, _} message
      # internally so handle_ssh_msg never sees it).
      assert [{name, {ExRatatui.SSH, sub_args}}] = daemon_opts[:subsystems]
      assert name == ~c"Elixir.ExRatatui.SSH.DaemonTest.SampleApp"
      assert sub_args[:mod] == SampleApp
      assert sub_args[:app_opts] == [foo: :bar]
      assert sub_args[:subsystem] == true
    end

    test "defaults app_opts to []" do
      opts = [mod: SampleApp]
      daemon_opts = Daemon.build_daemon_opts(SampleApp, opts)

      assert {ExRatatui.SSH, cli_args} = daemon_opts[:ssh_cli]
      assert cli_args[:app_opts] == []
    end

    test "coerces a binary :system_dir to a charlist" do
      daemon_opts =
        Daemon.build_daemon_opts(SampleApp, mod: SampleApp, system_dir: "/etc/ssh")

      assert daemon_opts[:system_dir] == ~c"/etc/ssh"
    end

    test "leaves a charlist :system_dir alone" do
      daemon_opts =
        Daemon.build_daemon_opts(SampleApp, mod: SampleApp, system_dir: ~c"/etc/ssh")

      assert daemon_opts[:system_dir] == ~c"/etc/ssh"
    end

    test "strips :auto_host_key before forwarding to :ssh.daemon/2" do
      daemon_opts =
        Daemon.build_daemon_opts(SampleApp,
          mod: SampleApp,
          auto_host_key: true,
          system_dir: ~c"/already/resolved"
        )

      refute Keyword.has_key?(daemon_opts, :auto_host_key)
      assert daemon_opts[:system_dir] == ~c"/already/resolved"
    end
  end

  describe "ensure_host_key!/1" do
    @describetag :tmp_dir
    @describetag capture_log: true

    test "creates the directory and generates an RSA host key", %{tmp_dir: tmp_dir} do
      dir = Path.join(tmp_dir, "ssh")
      refute File.exists?(dir)

      assert ^dir = to_string(Daemon.ensure_host_key!(dir))

      key_path = Path.join(dir, "ssh_host_rsa_key")
      assert File.exists?(key_path)

      pem = File.read!(key_path)
      assert pem =~ "BEGIN RSA PRIVATE KEY"

      # PEM should round-trip through :public_key
      [entry] = :public_key.pem_decode(pem)
      assert :RSAPrivateKey == elem(entry, 0)
    end

    test "returns the directory as a charlist", %{tmp_dir: tmp_dir} do
      dir = Path.join(tmp_dir, "ssh")
      result = Daemon.ensure_host_key!(dir)

      assert is_list(result)
      assert to_string(result) == dir
    end

    test "is idempotent — second call leaves the existing key alone", %{tmp_dir: tmp_dir} do
      dir = Path.join(tmp_dir, "ssh")
      _ = Daemon.ensure_host_key!(dir)

      key_path = Path.join(dir, "ssh_host_rsa_key")
      original = File.read!(key_path)
      original_mtime = File.stat!(key_path).mtime

      _ = Daemon.ensure_host_key!(dir)

      assert File.read!(key_path) == original
      assert File.stat!(key_path).mtime == original_mtime
    end

    test "writes the host key with 0600 permissions", %{tmp_dir: tmp_dir} do
      dir = Path.join(tmp_dir, "ssh")
      _ = Daemon.ensure_host_key!(dir)

      key_path = Path.join(dir, "ssh_host_rsa_key")
      mode = File.stat!(key_path).mode

      # Mask off file type bits — only the perms matter.
      assert Bitwise.band(mode, 0o777) == 0o600
    end
  end

  describe "resolve_host_key_opts/2" do
    test "is a no-op when :auto_host_key is absent or false" do
      opts = [mod: SampleApp, system_dir: ~c"/etc/ssh"]
      assert Daemon.resolve_host_key_opts(opts, SampleApp) == opts

      opts = [mod: SampleApp, auto_host_key: false]
      assert Daemon.resolve_host_key_opts(opts, SampleApp) == [mod: SampleApp]
    end

    test "raises when both :auto_host_key and :system_dir are passed" do
      opts = [auto_host_key: true, system_dir: ~c"/etc/ssh"]

      assert_raise ArgumentError, ~r/cannot pass both :auto_host_key and :system_dir/, fn ->
        Daemon.resolve_host_key_opts(opts, SampleApp)
      end
    end

    test "raises with a helpful message for non-boolean :auto_host_key values" do
      assert_raise ArgumentError, ~r/:auto_host_key must be a boolean/, fn ->
        Daemon.resolve_host_key_opts([auto_host_key: "yes"], SampleApp)
      end
    end

    test "raises when the OTP application can't be resolved" do
      # Pass a module name that isn't part of any loaded OTP application
      # so `Application.get_application/1` returns `nil`. The atom doesn't
      # need to point at a real module — `get_application` only consults
      # the app controller's manifest.
      assert_raise ArgumentError, ~r/could not resolve OTP application/, fn ->
        Daemon.resolve_host_key_opts(
          [auto_host_key: true],
          ExRatatui.SSH.DaemonTest.NotARealApp
        )
      end
    end
  end

  describe "ensure_app_host_key!/1 + resolve_host_key_opts/2 happy path" do
    @describetag :tmp_dir
    @describetag capture_log: true

    setup %{tmp_dir: tmp_dir} do
      fixture = temp_otp_app_fixture(tmp_dir)

      on_exit(fn ->
        _ = Application.unload(fixture.app)
        _ = :code.del_path(String.to_charlist(fixture.ebin))
      end)

      {:ok, mod: fixture.mod, ssh_dir: fixture.ssh_dir}
    end

    test "ensure_app_host_key!/1 resolves OTP app and generates a key under its priv/ssh",
         %{mod: mod, ssh_dir: ssh_dir} do
      result = Daemon.ensure_app_host_key!(mod)

      assert is_list(result)
      assert to_string(result) == ssh_dir
      assert File.exists?(Path.join(ssh_dir, "ssh_host_rsa_key"))
    end

    test "resolve_host_key_opts/2 injects :system_dir when :auto_host_key is true",
         %{mod: mod, ssh_dir: ssh_dir} do
      result = Daemon.resolve_host_key_opts([auto_host_key: true], mod)

      assert result[:system_dir] == String.to_charlist(ssh_dir)
      refute Keyword.has_key?(result, :auto_host_key)
    end
  end

  describe "auto_host_key end-to-end" do
    @describetag :tmp_dir
    @describetag capture_log: true

    test "init/1 generates a host key, sets system_dir, and starts the daemon", %{
      tmp_dir: tmp_dir
    } do
      fixture = temp_otp_app_fixture(tmp_dir)

      on_exit(fn ->
        _ = Application.unload(fixture.app)
        _ = :code.del_path(String.to_charlist(fixture.ebin))
      end)

      {:ok, pid} =
        Daemon.start_link(
          mod: fixture.mod,
          name: nil,
          port: 0,
          auto_host_key: true,
          daemon_starter: fake_starter(self()),
          daemon_stopper: fake_stopper(self())
        )

      assert_receive {:fake_started, 0, daemon_opts}, 1000
      assert daemon_opts[:system_dir] == String.to_charlist(fixture.ssh_dir)
      assert File.exists?(Path.join(fixture.ssh_dir, "ssh_host_rsa_key"))

      GenServer.stop(pid)
    end
  end
end
