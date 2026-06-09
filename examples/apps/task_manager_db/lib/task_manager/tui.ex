defmodule TaskManager.TUI do
  @moduledoc """
  Terminal UI for the Task Manager demo app.

  Uses `ExRatatui.App` to render a full CRUD interface backed by Ecto/SQLite.

  ## Layout

      +-------------------------------------------+
      | Task Manager                              |  header
      +-------------------------------------------+
      | All │ Todo │ In Progress │ Done            |  filter tabs
      +-------------------------------------------+
      | # | Title           | Status  | Priority  |  body (table + scrollbar)
      | 1 | Buy groceries   | Done    | ***       |
      | 2 | Write tests     | WIP     | **        |
      +-------------------------------------------+
      | New task: [____________________________]  |  input (when adding)
      +-------------------------------------------+
      | ============ 33% done                     |  gauge
      | j/k:nav Enter:toggle n:new d:del p:pri ...|  footer
      +-------------------------------------------+

  ## Key Bindings

  Normal mode:
    - `q` quit
    - `j`/Down move selection down
    - `k`/Up move selection up
    - Enter toggle task status
    - `n` new task (opens text input)
    - `d` delete selected task
    - `p` cycle priority
    - `f` cycle filter
    - Tab/Shift+Tab switch filter tab

  Input mode:
    - Enter confirm new task
    - Esc cancel
    - Left/Right/Home/End cursor navigation
    - Backspace/Delete edit text
    - Any printable char inserts at cursor
  """

  use ExRatatui.App

  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, LineGauge, Paragraph, Scrollbar, Table, Tabs, TextInput}

  @filters [:all, :todo, :in_progress, :done]
  @filter_labels ["All", "Todo", "In Progress", "Done"]

  # ── Callbacks ──────────────────────────────────────────────────

  @impl true
  def terminate(:normal, _state) do
    # In `:local` transport there's exactly one TUI process and it
    # owns the VM — pressing `q` should shut the whole app down. In
    # `:ssh` transport the TUI is one of many per-client sessions
    # under a long-lived daemon, so a single client quitting must not
    # take the daemon (or every other connected client) down with it.
    case Application.get_env(:task_manager, :transport, :local) do
      :local -> System.stop(0)
      _ -> :ok
    end
  end

  def terminate(_reason, _state), do: :ok

  @impl true
  def mount(_opts) do
    tasks = TaskManager.list_tasks(:all)
    {total, done} = TaskManager.completion_stats()

    {:ok,
     %{
       tasks: tasks,
       selected: 0,
       filter: :all,
       input_mode: nil,
       text_input: ExRatatui.text_input_new(),
       total: total,
       done: done
     }}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    input_height = if state.input_mode == :new_task, do: 3, else: 0

    [header_area, tabs_area, body_area, input_area, gauge_area, footer_area] =
      Layout.split(area, :vertical, [
        {:length, 3},
        {:length, 3},
        {:min, 0},
        {:length, input_height},
        {:length, 1},
        {:length, 3}
      ])

    # Table + scrollbar side by side
    table_width = body_area.width - 1
    table_area = %Rect{body_area | width: table_width}
    scrollbar_area = %Rect{body_area | x: body_area.x + table_width, width: 1}

    visible_rows = max(body_area.height - 3, 1)

    widgets = [
      {header_widget(state), header_area},
      {tabs_widget(state), tabs_area},
      {body_widget(state), table_area},
      {scrollbar_widget(state, visible_rows), scrollbar_area},
      {gauge_widget(state), gauge_area},
      {footer_widget(state), footer_area}
    ]

    widgets =
      if state.input_mode == :new_task do
        widgets ++ [{text_input_widget(state), input_area}]
      else
        widgets
      end

    widgets
  end

  @impl true
  def handle_event(
        %ExRatatui.Event.Key{code: code, kind: "press"},
        %{input_mode: :new_task} = state
      ) do
    handle_input_mode(code, state)
  end

  def handle_event(%ExRatatui.Event.Key{code: "q", kind: "press"}, %{input_mode: nil} = state) do
    {:stop, state}
  end

  def handle_event(%ExRatatui.Event.Key{code: code, kind: "press"}, %{input_mode: nil} = state)
      when code in ["j", "down"] do
    max_idx = max(length(state.tasks) - 1, 0)
    new_selected = min(state.selected + 1, max_idx)
    {:noreply, %{state | selected: new_selected}}
  end

  def handle_event(%ExRatatui.Event.Key{code: code, kind: "press"}, %{input_mode: nil} = state)
      when code in ["k", "up"] do
    new_selected = max(state.selected - 1, 0)
    {:noreply, %{state | selected: new_selected}}
  end

  def handle_event(%ExRatatui.Event.Key{code: "enter", kind: "press"}, %{input_mode: nil} = state) do
    state = toggle_selected_task(state)
    {:noreply, state}
  end

  def handle_event(%ExRatatui.Event.Key{code: "n", kind: "press"}, %{input_mode: nil} = state) do
    {:noreply, %{state | input_mode: :new_task}}
  end

  def handle_event(%ExRatatui.Event.Key{code: "d", kind: "press"}, %{input_mode: nil} = state) do
    state = delete_selected_task(state)
    {:noreply, state}
  end

  def handle_event(%ExRatatui.Event.Key{code: "p", kind: "press"}, %{input_mode: nil} = state) do
    state = cycle_selected_priority(state)
    {:noreply, state}
  end

  def handle_event(%ExRatatui.Event.Key{code: "f", kind: "press"}, %{input_mode: nil} = state) do
    next_filter = cycle_filter(state.filter)
    state = %{state | filter: next_filter}
    {:noreply, refresh_tasks(state)}
  end

  def handle_event(%ExRatatui.Event.Key{code: "tab", kind: "press"}, %{input_mode: nil} = state) do
    next_filter = cycle_filter(state.filter)
    state = %{state | filter: next_filter}
    {:noreply, refresh_tasks(state)}
  end

  def handle_event(
        %ExRatatui.Event.Key{code: "back_tab", kind: "press"},
        %{input_mode: nil} = state
      ) do
    next_filter = cycle_filter_back(state.filter)
    state = %{state | filter: next_filter}
    {:noreply, refresh_tasks(state)}
  end

  def handle_event(_event, state) do
    {:noreply, state}
  end

  # ── Input Mode Handling ────────────────────────────────────────

  defp handle_input_mode("enter", state) do
    title = ExRatatui.text_input_get_value(state.text_input) |> String.trim()

    state =
      if title == "" do
        %{state | input_mode: nil}
      else
        TaskManager.create_task(%{title: title})
        state = refresh_tasks(%{state | input_mode: nil})
        # Select the newly created task (last one in the list)
        %{state | selected: max(length(state.tasks) - 1, 0)}
      end

    ExRatatui.text_input_set_value(state.text_input, "")
    {:noreply, state}
  end

  defp handle_input_mode("esc", state) do
    ExRatatui.text_input_set_value(state.text_input, "")
    {:noreply, %{state | input_mode: nil}}
  end

  defp handle_input_mode(code, state) do
    ExRatatui.text_input_handle_key(state.text_input, code)
    {:noreply, state}
  end

  # ── Widgets ────────────────────────────────────────────────────

  defp header_widget(state) do
    task_count = length(state.tasks)

    %Paragraph{
      text: "  \u2728 Task Manager [#{task_count} tasks]",
      style: %Style{fg: :white, modifiers: [:bold]},
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: {:rgb, 100, 149, 237}}
      }
    }
  end

  defp tabs_widget(state) do
    selected = Enum.find_index(@filters, &(&1 == state.filter))

    %Tabs{
      titles: @filter_labels,
      selected: selected,
      style: %Style{fg: :dark_gray},
      highlight_style: %Style{fg: {:rgb, 100, 149, 237}, modifiers: [:bold]},
      divider: " │ ",
      block: %Block{
        title: " Filter ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: {:rgb, 60, 60, 80}}
      }
    }
  end

  defp body_widget(state) do
    rows =
      state.tasks
      |> Enum.with_index(1)
      |> Enum.map(fn {task, idx} ->
        [
          Integer.to_string(idx),
          task.title,
          status_display(task.status),
          priority_display(task.priority)
        ]
      end)

    selected =
      if length(state.tasks) > 0 do
        state.selected
      else
        nil
      end

    %Table{
      rows: rows,
      header: ["#", "Title", "Status", "Priority"],
      widths: [{:length, 4}, {:min, 10}, {:length, 16}, {:length, 10}],
      highlight_style: %Style{fg: {:rgb, 255, 215, 0}, bg: {:rgb, 40, 40, 60}, modifiers: [:bold]},
      highlight_symbol: " \u25B6 ",
      selected: selected,
      column_spacing: 2,
      block: %Block{
        title: " \u{1F4CB} Tasks ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: {:rgb, 100, 149, 237}}
      }
    }
  end

  defp scrollbar_widget(state, visible_rows) do
    total = length(state.tasks)

    %Scrollbar{
      content_length: max(total, 1),
      position: state.selected,
      viewport_content_length: visible_rows,
      thumb_style: %Style{fg: {:rgb, 100, 149, 237}},
      track_style: %Style{fg: {:rgb, 60, 60, 80}}
    }
  end

  defp text_input_widget(state) do
    %TextInput{
      state: state.text_input,
      style: %Style{fg: :white},
      cursor_style: %Style{fg: :black, bg: :white},
      placeholder: "Enter task title...",
      placeholder_style: %Style{fg: {:rgb, 100, 100, 120}},
      block: %Block{
        title: " \u270F\uFE0F  New Task (Enter = confirm, Esc = cancel) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: {:rgb, 255, 215, 0}}
      }
    }
  end

  defp gauge_widget(state) do
    ratio =
      if state.total > 0 do
        state.done / state.total
      else
        0.0
      end

    %LineGauge{
      ratio: ratio,
      label: "#{state.done}/#{state.total} tasks done",
      filled_style: %Style{fg: {:rgb, 80, 200, 120}},
      unfilled_style: %Style{fg: {:rgb, 60, 60, 80}}
    }
  end

  defp footer_widget(state) do
    text =
      if state.input_mode == :new_task do
        "  \u270F\uFE0F  Type task name, Enter to confirm, Esc to cancel"
      else
        "  j/\u2193 k/\u2191 Enter:toggle  n:new  d:del  p:priority  f/Tab:filter  q:quit"
      end

    %Paragraph{
      text: text,
      style: %Style{fg: {:rgb, 150, 150, 170}},
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: {:rgb, 60, 60, 80}}
      }
    }
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp refresh_tasks(state) do
    tasks = TaskManager.list_tasks(state.filter)
    {total, done} = TaskManager.completion_stats()
    selected = min(state.selected, max(length(tasks) - 1, 0))
    %{state | tasks: tasks, selected: selected, total: total, done: done}
  end

  defp toggle_selected_task(state) do
    task = Enum.at(state.tasks, state.selected)

    if task do
      TaskManager.toggle_status(task)
      refresh_tasks(state)
    else
      state
    end
  end

  defp delete_selected_task(state) do
    task = Enum.at(state.tasks, state.selected)

    if task do
      TaskManager.delete_task(task)
      refresh_tasks(state)
    else
      state
    end
  end

  defp cycle_selected_priority(state) do
    task = Enum.at(state.tasks, state.selected)

    if task do
      TaskManager.cycle_priority(task)
      refresh_tasks(state)
    else
      state
    end
  end

  defp cycle_filter(:all), do: :todo
  defp cycle_filter(:todo), do: :in_progress
  defp cycle_filter(:in_progress), do: :done
  defp cycle_filter(:done), do: :all

  defp cycle_filter_back(:all), do: :done
  defp cycle_filter_back(:done), do: :in_progress
  defp cycle_filter_back(:in_progress), do: :todo
  defp cycle_filter_back(:todo), do: :all

  defp status_display("done"), do: "\u2714 Done"
  defp status_display("in_progress"), do: "\u25B6 In Progress"
  defp status_display("todo"), do: "\u25CB Todo"
  defp status_display(other), do: "? #{other}"

  defp priority_display(1), do: "\u2605\u2605\u2605 High"
  defp priority_display(2), do: "\u2605\u2605  Med"
  defp priority_display(3), do: "\u2605   Low"
  defp priority_display(_), do: "\u2605\u2605  Med"
end
