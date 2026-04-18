defmodule ExRatatui.ExamplesTest do
  use ExUnit.Case, async: true

  @examples_dir Path.expand("../examples", __DIR__)

  for path <- Path.wildcard(Path.expand("../examples/*.exs", __DIR__)) do
    name = Path.basename(path, ".exs")

    test "#{name}.exs parses and compiles" do
      path = Path.join(@examples_dir, unquote(name) <> ".exs")
      code = File.read!(path)

      assert {:ok, _ast} = Code.string_to_quoted(code, file: path)
    end
  end

  # ---------------------------------------------------------------------------
  # Smoke tests: start each App-based example under test_mode, inject a quit
  # event, and assert it shuts down cleanly. This catches runtime regressions
  # that syntax-only tests miss.
  # ---------------------------------------------------------------------------

  # Extract module definitions and their supporting aliases from an example
  # script, compile them, and return the list of defined module names. This
  # keeps top-level `alias` directives (needed for struct expansion inside the
  # module) while skipping the tail-end runner code (start_link, receive, etc.).
  defp compile_example_modules(filename) do
    path = Path.join(@examples_dir, filename)
    code = File.read!(path)
    {:ok, ast} = Code.string_to_quoted(code, file: path)

    exprs =
      case ast do
        {:__block__, _, exprs} -> exprs
        expr -> [expr]
      end

    # Keep alias/require/import directives and defmodule blocks; drop runner
    # code (assignments, function calls, receive blocks) that would attempt
    # to start a real terminal.
    safe_exprs =
      Enum.filter(exprs, fn
        {:alias, _, _} -> true
        {:require, _, _} -> true
        {:import, _, _} -> true
        {:defmodule, _, _} -> true
        _ -> false
      end)

    block = {:__block__, [], safe_exprs}
    Code.eval_quoted(block, [], file: path)

    for {:defmodule, _, [{:__aliases__, _, parts} | _]} <- safe_exprs do
      Module.concat(parts)
    end
  end

  describe "App-based example smoke tests" do
    test "counter_app starts, renders, and stops on quit event" do
      compile_example_modules("counter_app.exs")

      {:ok, pid} = CounterApp.start_link(name: nil, test_mode: {40, 10})
      ref = Process.monitor(pid)

      snapshot = ExRatatui.Runtime.snapshot(pid)
      assert snapshot.mode == :callbacks
      assert snapshot.render_count >= 1

      quit = %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}
      :ok = ExRatatui.Runtime.inject_event(pid, quit)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
    end

    test "reducer_counter_app starts, renders, and stops on quit event" do
      compile_example_modules("reducer_counter_app.exs")

      {:ok, pid} = ReducerCounterApp.start_link(name: nil, test_mode: {40, 10})
      ref = Process.monitor(pid)

      snapshot = ExRatatui.Runtime.snapshot(pid)
      assert snapshot.mode == :reducer
      assert snapshot.render_count >= 1

      quit = %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}
      :ok = ExRatatui.Runtime.inject_event(pid, quit)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
    end

    test "widget_showcase starts, renders, and stops on Ctrl+C" do
      compile_example_modules("widget_showcase.exs")

      {:ok, pid} = WidgetShowcase.start_link(name: nil, test_mode: {80, 24})
      ref = Process.monitor(pid)

      snapshot = ExRatatui.Runtime.snapshot(pid)
      assert snapshot.mode == :callbacks
      assert snapshot.render_count >= 1

      quit = %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}
      :ok = ExRatatui.Runtime.inject_event(pid, quit)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
    end

    test "rich_text_showcase starts, renders, and stops on quit event" do
      compile_example_modules("rich_text_showcase.exs")

      {:ok, pid} = RichTextShowcase.start_link(name: nil, test_mode: {80, 24})
      ref = Process.monitor(pid)

      snapshot = ExRatatui.Runtime.snapshot(pid)
      assert snapshot.mode == :callbacks
      assert snapshot.render_count >= 1

      quit = %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}
      :ok = ExRatatui.Runtime.inject_event(pid, quit)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
    end
  end
end
