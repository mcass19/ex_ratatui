defmodule Mix.Tasks.ExRatatui.Gen.BurritoTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  describe "default invocation" do
    setup do
      igniter =
        test_project()
        |> Igniter.compose_task("ex_ratatui.gen.burrito", ["--tui-module", "Test.TUI"])

      {:ok, igniter: igniter}
    end

    test "adds burrito to deps", %{igniter: igniter} do
      assert_has_patch(igniter, "mix.exs", """
      + |      {:burrito, "~> 1.5"}
      """)
    end

    test "wires releases/0 with all four targets", %{igniter: igniter} do
      diff = diff(igniter)

      assert diff =~ "releases:"
      assert diff =~ "test:"
      assert diff =~ "linux: [os: :linux, cpu: :x86_64]"
      assert diff =~ "macos: [os: :darwin, cpu: :x86_64]"
      assert diff =~ "macos_silicon: [os: :darwin, cpu: :aarch64]"
      assert diff =~ "windows: [os: :windows, cpu: :x86_64]"
      assert diff =~ "&Burrito.wrap/1"
    end

    test "adds a Task child wired to the CLI entry point", %{igniter: igniter} do
      diff = diff(igniter)

      assert diff =~ "Task"
      assert diff =~ "Test.CLI.main(Burrito.Util.Args.argv())"
    end

    test "creates lib/test/cli.ex with main/1 and --version smoke", %{igniter: igniter} do
      assert_creates(igniter, "lib/test/cli.ex")

      diff = diff(igniter)
      assert diff =~ "defmodule Test.CLI do"
      assert diff =~ "def main(argv)"
      assert diff =~ ~s|IO.puts("test \#{@version}")|
      assert diff =~ "Test.TUI.start_link([])"
      assert diff =~ "Process.monitor(pid)"
      assert diff =~ "System.stop(0)"
    end

    test "creates .mise.toml pinning zig 0.15.2", %{igniter: igniter} do
      assert_creates(igniter, ".mise.toml")
      diff = diff(igniter)
      assert diff =~ ~s(zig = "0.15.2")
    end

    test "does not create a CI workflow by default", %{igniter: igniter} do
      refute_creates(igniter, ".github/workflows/release.yml")
    end

    test "prints next-steps notice", %{igniter: igniter} do
      assert_has_notice(
        igniter,
        &String.contains?(&1, "BURRITO_TARGET=linux MIX_ENV=prod mix release")
      )

      assert_has_notice(igniter, &String.contains?(&1, "./burrito_out/test_linux --version"))
    end
  end

  describe "with --ci github" do
    setup do
      igniter =
        test_project()
        |> Igniter.compose_task("ex_ratatui.gen.burrito", [
          "--tui-module",
          "Test.TUI",
          "--ci",
          "github"
        ])

      {:ok, igniter: igniter}
    end

    test "creates .github/workflows/release.yml", %{igniter: igniter} do
      assert_creates(igniter, ".github/workflows/release.yml")
    end

    test "workflow matrix covers all four targets", %{igniter: igniter} do
      diff = diff(igniter)

      assert diff =~ "ubuntu-latest"
      assert diff =~ "macos-13"
      assert diff =~ "macos-14"
      assert diff =~ "windows-latest"
      assert diff =~ "BURRITO_TARGET: ${{ matrix.target }}"
      assert diff =~ "softprops/action-gh-release"
    end

    test "notice mentions the tag-push trigger", %{igniter: igniter} do
      assert_has_notice(igniter, &String.contains?(&1, "git tag v0.1.0"))
    end
  end

  describe "with --ci none (explicit)" do
    test "matches default behaviour", %{} do
      igniter =
        test_project()
        |> Igniter.compose_task("ex_ratatui.gen.burrito", [
          "--tui-module",
          "Test.TUI",
          "--ci",
          "none"
        ])

      refute_creates(igniter, ".github/workflows/release.yml")
    end
  end
end
