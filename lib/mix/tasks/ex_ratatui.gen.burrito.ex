if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.ExRatatui.Gen.Burrito do
    @shortdoc "Scaffold Burrito packaging into the current project"

    @moduledoc """
    Patches the current project to ship as a single-file native binary via
    [Burrito](https://github.com/burrito-elixir/burrito).

    Adds `{:burrito, "~> 1.5"}`, wires `releases/0` with the four standard
    targets (linux, macos, macos_silicon, windows), creates a CLI module
    with a `main/1` entry point, adds a `.mise.toml` pinning `zig 0.15.2`,
    and — when `--ci github` is passed — drops a release workflow into
    `.github/workflows/`.

    See `guides/packaging/packaging_with_burrito.md` for the end-to-end
    story this task automates.

    ## Example

        mix ex_ratatui.gen.burrito --tui-module MyTui.TUI
        mix ex_ratatui.gen.burrito --tui-module MyTui.TUI --ci github

    ## Options

      * `--tui-module` (required) — the module that `use ExRatatui.App`. The
        generated CLI calls `that_module.start_link/1` and monitors it.
      * `--ci` — `none` (default) or `github`. With `github`, drops
        `.github/workflows/release.yml` that builds and publishes binaries
        on tag push.
    """

    use Igniter.Mix.Task

    alias Igniter.Project.Application, as: IgniterApp
    alias Igniter.Project.Deps, as: IgniterDeps
    alias Igniter.Project.MixProject, as: IgniterMixProject
    alias Igniter.Project.Module, as: IgniterModule

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :ex_ratatui,
        example: "mix ex_ratatui.gen.burrito --tui-module MyTui.TUI",
        schema: [
          tui_module: :string,
          ci: :string
        ],
        defaults: [ci: "none"],
        required: [:tui_module]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app = IgniterApp.app_name(igniter)
      options = igniter.args.options

      tui_module = IgniterModule.parse(options[:tui_module])
      cli_module = Module.concat([Macro.camelize("#{app}"), "CLI"])

      igniter
      |> IgniterDeps.add_dep({:burrito, "~> 1.5"})
      |> patch_releases(app)
      |> wire_application_child(cli_module)
      |> create_cli_module(cli_module, tui_module, app)
      |> create_mise_toml(app)
      |> maybe_create_ci_workflow(options[:ci], app)
      |> next_steps_notice(app, options[:ci])
    end

    defp patch_releases(igniter, app) do
      code = """
      [
        #{app}: [
          steps: [:assemble, &Burrito.wrap/1],
          burrito: [
            targets: [
              linux: [os: :linux, cpu: :x86_64],
              macos: [os: :darwin, cpu: :x86_64],
              macos_silicon: [os: :darwin, cpu: :aarch64],
              windows: [os: :windows, cpu: :x86_64]
            ]
          ]
        ]
      ]
      """

      {:ok, quoted} = Code.string_to_quoted(code)

      IgniterMixProject.update(igniter, :project, [:releases], fn _ ->
        {:ok, {:code, quoted}}
      end)
    end

    defp wire_application_child(igniter, cli_module) do
      # The `Burrito.Util.Args.argv()` reference lands literally in the
      # generated consumer module — aliasing it here would not propagate
      # into the quoted AST.
      # credo:disable-for-lines:5 Credo.Check.Design.AliasUsage
      task_fun =
        {:code,
         quote do
           fn -> unquote(cli_module).main(Burrito.Util.Args.argv()) end
         end}

      IgniterApp.add_new_child(igniter, {Task, task_fun})
    end

    defp create_cli_module(igniter, cli_module, tui_module, app) do
      content =
        render_template("cli.ex.eex",
          cli_module: cli_module,
          tui_module: tui_module,
          app: app
        )

      Igniter.Project.Module.create_module(igniter, cli_module, content)
    end

    defp create_mise_toml(igniter, app) do
      content = render_template("mise.toml.eex", app: app)
      Igniter.create_new_file(igniter, ".mise.toml", content, on_exists: :skip)
    end

    defp maybe_create_ci_workflow(igniter, "github", app) do
      content = render_template("release.yml.eex", app: app)

      Igniter.create_new_file(
        igniter,
        ".github/workflows/release.yml",
        content,
        on_exists: :skip
      )
    end

    defp maybe_create_ci_workflow(igniter, _, _), do: igniter

    defp render_template(name, assigns) do
      [:code.priv_dir(:ex_ratatui), "templates", "burrito", name]
      |> Path.join()
      |> EEx.eval_file(assigns: assigns)
    end

    defp next_steps_notice(igniter, app, ci) do
      body = """

      Next steps:

        1. mix deps.get
        2. mise install              (one-time; pins zig 0.15.2)
        3. BURRITO_TARGET=linux MIX_ENV=prod mix release --overwrite
        4. ./burrito_out/#{app}_linux --version

      For macos, macos_silicon, or windows artifacts, repeat step 3 on
      a host matching that OS — the bundled NIF is resolved from the
      build host's triple, so cross-host releases will not load. The
      generated CI workflow (if any) builds each target on its native
      runner.#{ci_note(ci)}

      Full walkthrough: https://hexdocs.pm/ex_ratatui/packaging_with_burrito.html
      """

      Igniter.add_notice(igniter, body)
    end

    defp ci_note("github"),
      do: "\n\nTag a release (git tag v0.1.0 && git push --tags) to fire the workflow."

    defp ci_note(_), do: ""
  end
else
  defmodule Mix.Tasks.ExRatatui.Gen.Burrito do
    @shortdoc "Scaffold Burrito packaging into the current project"

    @moduledoc """
    Scaffold Burrito packaging into the current project.

    Requires [Igniter](https://hex.pm/packages/igniter). Add it as a
    development dependency and try again:

        {:igniter, "~> 0.8", only: [:dev]}
    """

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'ex_ratatui.gen.burrito' requires igniter to be run.

      Add it as a development dependency:

          {:igniter, "~> 0.8", only: [:dev]}

      For more information, see: https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
