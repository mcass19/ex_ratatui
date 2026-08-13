defmodule ExRatatui.BurritoTest do
  # async: false — the wrapped-binary gate reads the __BURRITO env var.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  # Stub TUIs must not terminate before `main/3` has set its monitor, or
  # the DOWN reason arrives as :noproc instead of the intended one — so
  # each spins until it is monitored. Abnormal exits use spawn (no link):
  # the entry point unlinks right after monitoring, and racing the exit
  # into that window would kill the test process instead.
  defmodule Sync do
    def await_monitor do
      case Process.info(self(), :monitored_by) do
        {:monitored_by, []} -> await_monitor()
        _ -> :ok
      end
    end
  end

  defmodule NormalExit do
    alias ExRatatui.BurritoTest.Sync

    def start_link([]) do
      {:ok, spawn_link(fn -> Sync.await_monitor() end)}
    end
  end

  defmodule ShutdownTupleExit do
    alias ExRatatui.BurritoTest.Sync

    def start_link([]) do
      {:ok,
       spawn(fn ->
         Sync.await_monitor()
         exit({:shutdown, :done})
       end)}
    end
  end

  defmodule CrashExit do
    alias ExRatatui.BurritoTest.Sync

    def start_link([]) do
      {:ok,
       spawn(fn ->
         Sync.await_monitor()
         exit(:boom)
       end)}
    end
  end

  defmodule FailsToStart do
    def start_link([]), do: {:error, {:terminal_init_failed, :enotty}}
  end

  defmodule Raises do
    def start_link([]), do: raise("no tty for you")
  end

  defp standalone(fun) do
    System.put_env("__BURRITO", "1")
    fun.()
  after
    System.delete_env("__BURRITO")
  end

  defp halt_fun(test_pid), do: fn code -> send(test_pid, {:halted, code}) end

  describe "main/3" do
    test "is a no-op outside a burrito-wrapped binary" do
      System.delete_env("__BURRITO")

      assert :ok =
               ExRatatui.Burrito.main(CrashExit, [], name: "demo", halt: halt_fun(self()))

      refute_receive {:halted, _}
    end

    test "--version anywhere in argv prints name and version and exits 0" do
      standalone(fn ->
        output =
          capture_io(fn ->
            ExRatatui.Burrito.main(NormalExit, ["--verbose", "--version"],
              name: "demo",
              version: "1.2.3",
              halt: halt_fun(self())
            )
          end)

        assert output == "demo 1.2.3\n"
        assert_receive {:halted, 0}
      end)
    end

    test "exits 0 when the TUI stops normally" do
      standalone(fn ->
        ExRatatui.Burrito.main(NormalExit, [], name: "demo", halt: halt_fun(self()))
        assert_receive {:halted, 0}
      end)
    end

    test "exits 0 on a {:shutdown, _} stop" do
      standalone(fn ->
        ExRatatui.Burrito.main(ShutdownTupleExit, [], name: "demo", halt: halt_fun(self()))
        assert_receive {:halted, 0}
      end)
    end

    test "exits 1 with a message when the TUI crashes" do
      standalone(fn ->
        stderr =
          capture_io(:stderr, fn ->
            ExRatatui.Burrito.main(CrashExit, [], name: "demo", halt: halt_fun(self()))
            assert_receive {:halted, 1}
          end)

        assert stderr =~ "demo terminated: :boom"
      end)
    end

    test "exits 1 with a message when the TUI fails to start" do
      standalone(fn ->
        stderr =
          capture_io(:stderr, fn ->
            ExRatatui.Burrito.main(FailsToStart, [], name: "demo", halt: halt_fun(self()))
            assert_receive {:halted, 1}
          end)

        assert stderr =~ "demo failed to start: {:terminal_init_failed, :enotty}"
      end)
    end

    test "rescues a raise in the entry point and exits 1" do
      standalone(fn ->
        stderr =
          capture_io(:stderr, fn ->
            ExRatatui.Burrito.main(Raises, [], name: "demo", halt: halt_fun(self()))
            assert_receive {:halted, 1}
          end)

        assert stderr =~ "demo crashed: no tty for you"
      end)
    end
  end

  describe "start_link/3" do
    test "outside a wrapped binary, starts an async no-op task" do
      System.delete_env("__BURRITO")

      assert {:ok, pid} =
               ExRatatui.Burrito.start_link(CrashExit, [], name: "demo", halt: halt_fun(self()))

      assert is_pid(pid)
      refute_receive {:halted, _}
    end

    test "inside a wrapped binary, runs the TUI synchronously and then halts" do
      standalone(fn ->
        # Synchronous: blocks until the stub TUI exits, so the halt has
        # already fired by the time start_link/3 returns.
        assert :ignore =
                 ExRatatui.Burrito.start_link(NormalExit, [],
                   name: "demo",
                   halt: halt_fun(self())
                 )

        assert_received {:halted, 0}
      end)
    end
  end

  describe "verify_linux_nif/2" do
    # The loaded artifact is whatever this build resolved, so the fixture
    # names it the way the release step learns it — never by hardcoding a
    # filename, which would only hold for one ABI and build mode.
    @load_from {:ex_ratatui,
                "priv/native/libex_ratatui-v0.12.0-nif-2.17-x86_64-unknown-linux-musl"}

    setup do
      root = Path.join(System.tmp_dir!(), "burrito_verify_#{System.unique_integer([:positive])}")
      nif_dir = Path.join(root, "lib/ex_ratatui-0.12.0/priv/native")
      File.mkdir_p!(nif_dir)
      on_exit(fn -> File.rm_rf(root) end)

      {:ok, release: %{path: root}, nif_dir: nif_dir, nif: nif_path(root, @load_from)}
    end

    defp nif_path(root, {_otp_app, relative_path}) do
      Path.join([root, "lib/ex_ratatui-0.12.0", relative_path <> ".so"])
    end

    defp linux_target(fun) do
      System.put_env("BURRITO_TARGET", "linux")
      fun.()
    after
      System.delete_env("BURRITO_TARGET")
    end

    test "passes a musl NIF through unchanged", %{release: release, nif: nif} do
      File.write!(nif, "\x7fELF...libc.so\x00...")

      linux_target(fn ->
        assert ExRatatui.Burrito.verify_linux_nif(release, @load_from) == release
      end)
    end

    test "ignores the stale artifacts alongside it", %{
      release: release,
      nif_dir: nif_dir,
      nif: nif
    } do
      File.write!(nif, "\x7fELF...libc.so\x00...")
      File.write!(Path.join(nif_dir, "ex_ratatui.so"), "\x7fELF...libc.so.6\x00...")

      File.write!(
        Path.join(nif_dir, "libex_ratatui-v0.11.2-nif-2.17-x86_64-unknown-linux-gnu.so"),
        "\x7fELF...GLIBC_2.17\x00..."
      )

      linux_target(fn ->
        assert ExRatatui.Burrito.verify_linux_nif(release, @load_from) == release
      end)
    end

    test "defaults to the NIF this build loads", %{release: release} do
      nif = nif_path(release.path, ExRatatui.Native.load_from())
      File.mkdir_p!(Path.dirname(nif))
      File.write!(nif, "\x7fELF...libc.so\x00...")

      linux_target(fn ->
        assert ExRatatui.Burrito.verify_linux_nif(release) == release
      end)
    end

    test "raises on a glibc NIF (libc.so.6 marker)", %{release: release, nif: nif} do
      File.write!(nif, "\x7fELF...libc.so.6\x00...")

      linux_target(fn ->
        assert_raise Mix.Error, ~r/glibc NIF.*TARGET_ABI=musl.*EX_RATATUI_BUILD/s, fn ->
          ExRatatui.Burrito.verify_linux_nif(release, @load_from)
        end
      end)
    end

    test "raises on a glibc NIF (GLIBC_ version marker)", %{release: release, nif: nif} do
      File.write!(nif, "\x7fELF...GLIBC_2.17\x00...")

      linux_target(fn ->
        assert_raise Mix.Error, ~r/glibc NIF/, fn ->
          ExRatatui.Burrito.verify_linux_nif(release, @load_from)
        end
      end)
    end

    test "raises when the release contains no NIF to verify", %{release: release} do
      linux_target(fn ->
        assert_raise Mix.Error, ~r/no ex_ratatui NIF found/, fn ->
          ExRatatui.Burrito.verify_linux_nif(release, @load_from)
        end
      end)
    end

    test "is a no-op for non-linux targets", %{release: release, nif: nif} do
      File.write!(nif, "\x7fELF...GLIBC_2.17\x00...")

      System.delete_env("BURRITO_TARGET")
      assert ExRatatui.Burrito.verify_linux_nif(release, @load_from) == release
    end
  end
end
