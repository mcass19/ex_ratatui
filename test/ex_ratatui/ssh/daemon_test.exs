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

      # Our channel wire-up is present
      assert {ExRatatui.SSH, cli_args} = daemon_opts[:ssh_cli]
      assert cli_args[:mod] == SampleApp
      assert cli_args[:app_opts] == [foo: :bar]
      assert daemon_opts[:exec] == :disabled

      # Subsystem carries the same cli_args so `ssh -s <name>` works too
      assert [{name, {ExRatatui.SSH, sub_args}}] = daemon_opts[:subsystems]
      assert name == ~c"Elixir.ExRatatui.SSH.DaemonTest.SampleApp"
      assert sub_args[:mod] == SampleApp
      assert sub_args[:app_opts] == [foo: :bar]
    end

    test "defaults app_opts to []" do
      opts = [mod: SampleApp]
      daemon_opts = Daemon.build_daemon_opts(SampleApp, opts)

      assert {ExRatatui.SSH, cli_args} = daemon_opts[:ssh_cli]
      assert cli_args[:app_opts] == []
    end
  end
end
