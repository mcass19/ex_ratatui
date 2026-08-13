defmodule Mix.Tasks.ExRatatui.Gen.BurritoTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  defp created_content(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end

  describe "default invocation" do
    setup do
      igniter =
        test_project()
        |> Igniter.compose_task("ex_ratatui.gen.burrito", ["--tui-module", "Test.TUI"])

      {:ok, igniter: igniter}
    end

    test "adds burrito to deps", %{igniter: igniter} do
      assert_has_patch(igniter, "mix.exs", """
      + |      {:burrito, "~> 1.6"}
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
      assert diff =~ "&ExRatatui.Burrito.verify_linux_nif/1"
      assert diff =~ "&Burrito.wrap/1"
    end

    test "adds the CLI module as a supervised child", %{igniter: igniter} do
      diff = diff(igniter)

      assert diff =~ "Test.CLI"
      refute diff =~ "{Task,"
    end

    # The strongest regression guard for the generated module shape: the
    # content must compile to exactly one module, named Test.CLI, exporting
    # main/1. A template that carries its own `defmodule` wrapper compiles
    # to a nested Test.CLI.Test.CLI instead and this fails.
    test "generated CLI compiles to a single module exporting main/1", %{igniter: igniter} do
      content = created_content(igniter, "lib/test/cli.ex")

      # with_diagnostics swallows the expected warnings about modules that
      # only exist in a scaffolded consumer (Burrito.Util, Test.TUI).
      {compiled, _diagnostics} =
        Code.with_diagnostics(fn -> Code.compile_string(content) end)

      modules = Enum.map(compiled, &elem(&1, 0))

      try do
        assert modules == [Test.CLI]
        assert function_exported?(Test.CLI, :start_link, 1)
      after
        Enum.each(modules, fn mod ->
          :code.purge(mod)
          :code.delete(mod)
        end)
      end
    end

    test "creates lib/test/cli.ex as a thin shim over ExRatatui.Burrito", %{igniter: igniter} do
      assert_creates(igniter, "lib/test/cli.ex")

      content = created_content(igniter, "lib/test/cli.ex")
      assert content =~ "use Task"

      assert content =~
               ~s|ExRatatui.Burrito.start_link(Test.TUI, Burrito.Util.Args.argv(),|

      assert content =~ ~s|name: "test"|
      assert content =~ "version: @version"
    end

    test "creates .mise.toml pinning zig 0.16.0", %{igniter: igniter} do
      assert_creates(igniter, ".mise.toml")
      diff = diff(igniter)
      assert diff =~ ~s(zig = "0.16.0")
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

  describe "releases merging" do
    test "preserves existing releases entries" do
      igniter =
        [files: %{"mix.exs" => mix_exs(releases: "[existing: [include_erts: false]]")}]
        |> test_project()
        |> Igniter.compose_task("ex_ratatui.gen.burrito", ["--tui-module", "Test.TUI"])

      content = created_content(igniter, "mix.exs")
      assert content =~ "existing: [include_erts: false]"
      assert content =~ "&Burrito.wrap/1"
    end

    test "keeps an existing entry for this app and warns that it will not wrap" do
      igniter =
        [files: %{"mix.exs" => mix_exs(releases: "[test: [steps: [:assemble]]]")}]
        |> test_project()
        |> Igniter.compose_task("ex_ratatui.gen.burrito", ["--tui-module", "Test.TUI"])

      content = created_content(igniter, "mix.exs")
      assert content =~ "test: [steps: [:assemble]]"
      refute content =~ "&Burrito.wrap/1"
      assert Enum.any?(igniter.warnings, &(&1 =~ "already has a `test:` entry"))
    end

    test "merges into a private function reference instead of clobbering it" do
      igniter =
        [files: %{"mix.exs" => mix_exs(releases: "releases()", private: "defp releases, do: []")}]
        |> test_project()
        |> Igniter.compose_task("ex_ratatui.gen.burrito", ["--tui-module", "Test.TUI"])

      content = created_content(igniter, "mix.exs")
      assert content =~ "releases: releases()"
      assert content =~ "&Burrito.wrap/1"
    end

    test "warns instead of clobbering a non-literal releases value" do
      igniter =
        [files: %{"mix.exs" => mix_exs(releases: "Keyword.merge([], [])")}]
        |> test_project()
        |> Igniter.compose_task("ex_ratatui.gen.burrito", ["--tui-module", "Test.TUI"])

      assert Enum.any?(igniter.warnings, &(&1 =~ "not a literal keyword list"))
      assert created_content(igniter, "mix.exs") =~ "releases: Keyword.merge([], [])"
    end
  end

  describe "application wiring" do
    test "wires the CLI alongside an unrelated Task child" do
      files = %{
        "mix.exs" => mix_exs(application: "[mod: {Test.Application, []}]"),
        "lib/test/application.ex" => """
        defmodule Test.Application do
          use Application

          def start(_type, _args) do
            children = [
              {Task, fn -> :already_here end}
            ]

            Supervisor.start_link(children, strategy: :one_for_one)
          end
        end
        """
      }

      igniter =
        [files: files]
        |> test_project()
        |> Igniter.compose_task("ex_ratatui.gen.burrito", ["--tui-module", "Test.TUI"])

      content = created_content(igniter, "lib/test/application.ex")
      assert content =~ "{Task, fn -> :already_here end}"
      assert content =~ "Test.CLI"
      assert igniter.warnings == []
    end

    test "re-running the generator does not duplicate the child" do
      igniter =
        test_project()
        |> Igniter.compose_task("ex_ratatui.gen.burrito", ["--tui-module", "Test.TUI"])
        |> Igniter.compose_task("ex_ratatui.gen.burrito", ["--tui-module", "Test.TUI"])

      content = created_content(igniter, "lib/test/application.ex")
      assert length(String.split(content, "Test.CLI")) == 2
    end
  end

  describe "template/demo sync" do
    # examples/burrito_demo is documented as exactly what the generator
    # produces — these tests pin the demo files to the real generator
    # output so a fix to either side cannot silently strand the other.
    setup do
      igniter =
        [app_name: :burrito_demo]
        |> test_project()
        |> Igniter.compose_task("ex_ratatui.gen.burrito", [
          "--tui-module",
          "BurritoDemo.Counter"
        ])

      {:ok, igniter: igniter}
    end

    test "demo CLI is byte-identical to the generated one", %{igniter: igniter} do
      generated = created_content(igniter, "lib/burrito_demo/cli.ex")
      assert generated == File.read!("examples/burrito_demo/lib/burrito_demo/cli.ex")
    end

    test "demo .mise.toml is byte-identical to the generated one", %{igniter: igniter} do
      generated = created_content(igniter, ".mise.toml")
      assert generated == File.read!("examples/burrito_demo/.mise.toml")
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
      assert diff =~ "macos-15-intel"
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

  describe "with an unknown --ci value" do
    test "reports an issue instead of silently skipping" do
      igniter =
        test_project()
        |> Igniter.compose_task("ex_ratatui.gen.burrito", [
          "--tui-module",
          "Test.TUI",
          "--ci",
          "gitlab"
        ])

      assert Enum.any?(igniter.issues, &(&1 =~ ~s(unknown --ci value "gitlab")))
    end
  end

  defp mix_exs(opts) do
    releases =
      case opts[:releases] do
        nil -> ""
        releases -> ",\n        releases: #{releases}"
      end

    application =
      case opts[:application] do
        nil -> "[extra_applications: [:logger]]"
        application -> application
      end

    """
    defmodule Test.MixProject do
      use Mix.Project

      def project do
        [
          app: :test,
          version: "0.1.0",
          elixir: "~> 1.17",
          start_permanent: Mix.env() == :prod,
          deps: deps()#{releases}
        ]
      end

      def application do
        #{application}
      end

      defp deps do
        []
      end

      #{opts[:private]}
    end
    """
  end
end
