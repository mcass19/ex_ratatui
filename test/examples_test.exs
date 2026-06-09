defmodule ExRatatui.ExamplesTest do
  use ExUnit.Case, async: true

  # These modules are compiled at runtime via `compile_example_modules/1`
  # from examples/**/*.exs, so the compiler can't see them statically.
  @compile {:no_warn_undefined,
            [
              BarChartDemo,
              CalendarDemo,
              CanvasDemo,
              ChartDemo,
              ChatApp,
              CheckboxDemo,
              ClearDemo,
              CounterApp,
              CustomWidgetsExample,
              GaugeDemo,
              LineGaugeDemo,
              ListDemo,
              MarkdownDemo,
              PopupDemo,
              ReducerCounterApp,
              RichTextShowcase,
              ScrollbarDemo,
              SlashCommandsDemo,
              SparklineDemo,
              StateMachineDemo,
              SystemMonitor,
              TabsDemo,
              TelemetryDemo,
              TextareaDemo,
              ThrobberDemo,
              WidgetListDemo
            ]}

  @examples_dir Path.expand("../examples", __DIR__)

  # The examples directory now uses subfolders. Walk it recursively, but skip
  # the self-contained mix sub-projects: they ship their own mix.exs / config /
  # test .exs files (and a `task_manager_db/` Ecto app), which must not be
  # swept into the parse test. `burrito_demo/` is untracked but still on disk.
  @excluded_prefixes ["apps/task_manager_db/", "burrito_demo/"]

  example_files =
    Path.join(@examples_dir, "**/*.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, @examples_dir))
    |> Enum.reject(fn rel -> Enum.any?(@excluded_prefixes, &String.starts_with?(rel, &1)) end)
    |> Enum.sort()

  for rel <- example_files do
    test "#{rel} parses and compiles" do
      path = Path.join(@examples_dir, unquote(rel))
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
  defp compile_example_modules(rel_path) do
    path = Path.join(@examples_dir, rel_path)
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

  # App-based examples that are safe to drive headlessly: each starts under
  # `test_mode`, renders at least once, and stops cleanly on `q`. New isolates
  # that `use ExRatatui.App` get a row here as they are added.
  @app_smoke_examples [
    {"basics/counter_app.exs", CounterApp, :callbacks},
    {"basics/reducer_counter_app.exs", ReducerCounterApp, :reducer},
    {"widgets/barchart.exs", BarChartDemo, :callbacks},
    {"widgets/calendar.exs", CalendarDemo, :callbacks},
    {"widgets/canvas.exs", CanvasDemo, :callbacks},
    {"widgets/chart.exs", ChartDemo, :callbacks},
    {"widgets/checkbox.exs", CheckboxDemo, :callbacks},
    {"widgets/markdown.exs", MarkdownDemo, :callbacks},
    {"widgets/popup.exs", PopupDemo, :callbacks},
    {"widgets/rich_text.exs", RichTextShowcase, :callbacks},
    {"widgets/slash_commands.exs", SlashCommandsDemo, :callbacks},
    {"widgets/sparkline.exs", SparklineDemo, :callbacks},
    {"widgets/throbber.exs", ThrobberDemo, :reducer},
    {"widgets/widget_list.exs", WidgetListDemo, :callbacks},
    {"widgets/custom_widget.exs", CustomWidgetsExample, :callbacks},
    {"widgets/gauge.exs", GaugeDemo, :callbacks},
    {"widgets/line_gauge.exs", LineGaugeDemo, :callbacks},
    {"widgets/scrollbar.exs", ScrollbarDemo, :callbacks},
    {"widgets/tabs.exs", TabsDemo, :callbacks},
    {"widgets/list.exs", ListDemo, :callbacks},
    {"widgets/textarea.exs", TextareaDemo, :callbacks},
    {"widgets/clear.exs", ClearDemo, :callbacks},
    {"observability/telemetry.exs", TelemetryDemo, :callbacks}
  ]

  describe "App-based example smoke tests" do
    for {rel, mod, mode} <- @app_smoke_examples do
      test "#{rel} starts, renders, and stops on quit event" do
        compile_example_modules(unquote(rel))

        {:ok, pid} = unquote(mod).start_link(name: nil, test_mode: {80, 24})
        ref = Process.monitor(pid)

        snapshot = ExRatatui.Runtime.snapshot(pid)
        assert snapshot.mode == unquote(mode)
        assert snapshot.render_count >= 1

        quit = %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}
        :ok = ExRatatui.Runtime.inject_event(pid, quit)

        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
      end
    end

    # system_monitor reads from /proc, /sys, :os.cmd("df"), :inet.getifaddrs.
    # All readers fall back to safe defaults (nil / %{total: 0, used: 0} / [])
    # when the source is missing, so the test doesn't need to mock the host —
    # it just has to tolerate both "real Linux box" and "CI sandbox" outcomes.
    test "apps/system_monitor.exs starts, renders, and stops on quit event" do
      compile_example_modules("apps/system_monitor.exs")

      {:ok, pid} = SystemMonitor.start_link(name: nil, test_mode: {80, 24})
      ref = Process.monitor(pid)

      snapshot = ExRatatui.Runtime.snapshot(pid)
      assert snapshot.mode == :callbacks
      assert snapshot.render_count >= 1

      # Refresh key path: collect_stats runs again, render_count bumps.
      refresh = %ExRatatui.Event.Key{code: "r", modifiers: [], kind: "press"}
      :ok = ExRatatui.Runtime.inject_event(pid, refresh)

      # Give the server a moment to process the event and re-render.
      _ = :sys.get_state(pid)
      bumped = ExRatatui.Runtime.snapshot(pid)
      assert bumped.render_count > snapshot.render_count

      quit = %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}
      :ok = ExRatatui.Runtime.inject_event(pid, quit)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
    end

    # state_machine's "q" opens a confirm-quit overlay instead of quitting, so
    # the generic table can't drive it. Walk the modal flow: q opens it, y
    # confirms and stops.
    test "observability/state_machine.exs opens the quit modal and stops on confirm" do
      compile_example_modules("observability/state_machine.exs")

      {:ok, pid} = StateMachineDemo.start_link(name: nil, test_mode: {80, 24})
      ref = Process.monitor(pid)

      assert ExRatatui.Runtime.snapshot(pid).render_count >= 1

      # q opens the overlay but must NOT stop the app.
      quit_key = %ExRatatui.Event.Key{code: "q", modifiers: [], kind: "press"}
      :ok = ExRatatui.Runtime.inject_event(pid, quit_key)
      _ = :sys.get_state(pid)
      refute_received {:DOWN, ^ref, :process, ^pid, _}

      # y confirms and the app shuts down cleanly.
      confirm = %ExRatatui.Event.Key{code: "y", modifiers: [], kind: "press"}
      :ok = ExRatatui.Runtime.inject_event(pid, confirm)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
    end
  end

  # apps/chat.exs uses the raw `ExRatatui.run/1 + poll_event` loop — no
  # `use ExRatatui.App`, so there's no Server to start_link and no
  # `test_mode` seam. Instead we compile the module, then exercise the
  # two public pieces the example depends on against a test terminal:
  # the `SlashCommands.parse`/`match_commands` pipeline and the widget
  # stack (Textarea + Markdown + WidgetList) it composes per frame.
  describe "raw-run example smoke tests" do
    alias ExRatatui.Layout.Rect
    alias ExRatatui.Native
    alias ExRatatui.Widgets.{Block, Markdown, Paragraph, Textarea, WidgetList}
    alias ExRatatui.Widgets.SlashCommands
    alias ExRatatui.Widgets.SlashCommands.Command

    test "apps/chat.exs compiles and its widget stack draws to a test terminal" do
      compile_example_modules("apps/chat.exs")

      # The compiled module must expose `run/0`, the raw entry point.
      assert function_exported?(ChatApp, :run, 0)

      # --- slash-command pipeline the example relies on ----------------
      commands = [
        %Command{name: "help", description: "Show available commands"},
        %Command{name: "quit", description: "Exit the chat", aliases: ["exit", "q"]}
      ]

      assert {:command, "he"} = SlashCommands.parse("/he")
      assert :no_command = SlashCommands.parse("hello")

      matched = SlashCommands.match_commands(commands, "he")
      assert [%Command{name: "help"} | _] = matched

      # --- draw the example's frame shape to a test terminal -----------
      terminal = ExRatatui.init_test_terminal(80, 24)
      on_exit(fn -> Native.restore_terminal(terminal) end)

      textarea_state = ExRatatui.textarea_new()

      header = %Paragraph{text: "AI Chat Interface"}

      items = [
        {%Paragraph{text: " You "}, 1},
        {%Markdown{content: "hello **world**"}, 1},
        {%Paragraph{text: ""}, 1},
        {%Paragraph{text: " AI "}, 1},
        {%Markdown{content: "# reply\n\n- item"}, 3}
      ]

      message_list = %WidgetList{
        items: items,
        scroll_offset: 0,
        block: %Block{title: "Chat", borders: [:all]}
      }

      textarea = %Textarea{
        state: textarea_state,
        placeholder: "Type a message...",
        block: %Block{title: "Message", borders: [:all]}
      }

      widgets = [
        {header, %Rect{x: 0, y: 0, width: 80, height: 1}},
        {message_list, %Rect{x: 0, y: 1, width: 80, height: 18}},
        {textarea, %Rect{x: 0, y: 19, width: 80, height: 5}}
      ]

      assert :ok = ExRatatui.draw(terminal, widgets)

      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "AI Chat Interface"
      assert content =~ "Chat"
      assert content =~ "Message"
      assert content =~ "hello"
      assert content =~ "reply"
    end
  end
end
