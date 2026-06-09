# Example: interactive task tracker showcasing most widgets.
# Run with: mix run examples/apps/task_manager.exs
#
# Each team member has their own task board. Navigate between members
# to see and manage their individual tasks.
#
# Controls:
#   Tab       = cycle focus between team list and task board
#   Up/k      = move selection up
#   Down/j    = move selection down
#   Enter     = toggle task status (Todo → In Progress → Done → Todo)
#   n         = create a new task for the selected member
#   d         = delete selected task
#   q         = quit

alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, LineGauge, List, Paragraph, Scrollbar, Table, Tabs, TextInput}
alias ExRatatui.Event

defmodule TaskTracker do
  @team ["Alice", "Bob", "Carol", "Dave", "Eve"]
  @panels [:team, :tasks]
  @boards %{
    "Alice" => [
      %{id: "EX-101", name: "Implement login", status: "Done"},
      %{id: "EX-102", name: "Add OAuth provider", status: "In Progress"},
      %{id: "EX-103", name: "Write auth tests", status: "Todo"}
    ],
    "Bob" => [
      %{id: "EX-201", name: "Design search API", status: "Done"},
      %{id: "EX-202", name: "Add full-text index", status: "In Progress"},
      %{id: "EX-203", name: "Implement filters", status: "Todo"},
      %{id: "EX-204", name: "Search pagination", status: "Todo"}
    ],
    "Carol" => [
      %{id: "EX-301", name: "Fix N+1 query", status: "Done"},
      %{id: "EX-302", name: "Add query cache", status: "Done"},
      %{id: "EX-303", name: "Profile dashboard", status: "In Progress"}
    ],
    "Dave" => [
      %{id: "EX-401", name: "Set up CI pipeline", status: "Done"},
      %{id: "EX-402", name: "Add deploy scripts", status: "In Progress"},
      %{id: "EX-403", name: "Configure staging", status: "Todo"},
      %{id: "EX-404", name: "Write runbook", status: "Todo"}
    ],
    "Eve" => [
      %{id: "EX-501", name: "Update API docs", status: "In Progress"},
      %{id: "EX-502", name: "Write onboarding guide", status: "Todo"}
    ]
  }

  def run do
    ExRatatui.run(fn terminal ->
      loop(terminal, %{
        focus: :team,
        team_selected: 0,
        task_selected: 0,
        boards: @boards,
        next_id: 600,
        input_mode: nil,
        text_input: ExRatatui.text_input_new(),
        tick: 0
      })
    end)
  end

  defp current_member(state), do: Enum.at(@team, state.team_selected)
  defp current_tasks(state), do: Map.get(state.boards, current_member(state), [])

  defp update_board(state, tasks) do
    %{state | boards: Map.put(state.boards, current_member(state), tasks)}
  end

  defp loop(terminal, state) do
    {w, h} = ExRatatui.terminal_size()
    area = %Rect{x: 0, y: 0, width: w, height: h}

    # Main layout: header, body, input (conditional), footer
    input_height = if state.input_mode == :new_task, do: 3, else: 0

    [header_area, body_area, input_area, gauge_area, status_area] =
      Layout.split(area, :vertical, [
        {:length, 3},
        {:min, 0},
        {:length, input_height},
        {:length, 1},
        {:length, 2}
      ])

    # Body: sidebar (team list) | main (task table)
    [sidebar_area, main_area] =
      Layout.split(body_area, :horizontal, [{:percentage, 25}, {:percentage, 75}])

    # Task table area: table + scrollbar
    tasks = current_tasks(state)
    table_width = main_area.width - 1
    table_area = %Rect{main_area | width: table_width}
    scrollbar_area = %Rect{main_area | x: main_area.x + table_width, width: 1}

    # Visible rows inside the block (borders take 2 rows, header takes 1)
    visible_rows = max(main_area.height - 3, 1)

    widgets = [
      {header_widget(state), header_area},
      {team_widget(state), sidebar_area},
      {tasks_widget(state), table_area},
      {scrollbar_widget(tasks, state.task_selected, visible_rows), scrollbar_area},
      {gauge_widget(state), gauge_area},
      {status_widget(state), status_area}
    ]

    widgets =
      if state.input_mode == :new_task do
        widgets ++ [{text_input_widget(state), input_area}]
      else
        widgets
      end

    ExRatatui.draw(terminal, widgets)

    case ExRatatui.poll_event(100) do
      %Event.Key{code: "q", kind: "press"} when state.input_mode == nil ->
        :ok

      # --- Input mode: typing a new task name ---
      %Event.Key{code: "enter", kind: "press"} when state.input_mode == :new_task ->
        state = create_task(state)
        ExRatatui.text_input_set_value(state.text_input, "")
        loop(terminal, %{state | input_mode: nil, tick: state.tick + 1})

      %Event.Key{code: "esc", kind: "press"} when state.input_mode != nil ->
        ExRatatui.text_input_set_value(state.text_input, "")
        loop(terminal, %{state | input_mode: nil, tick: state.tick + 1})

      %Event.Key{code: code, kind: "press"} when state.input_mode != nil ->
        ExRatatui.text_input_handle_key(state.text_input, code)
        loop(terminal, %{state | tick: state.tick + 1})

      # --- Normal mode ---
      %Event.Key{code: "tab", kind: "press"} ->
        loop(terminal, %{state | focus: next_panel(state.focus), tick: state.tick + 1})

      %Event.Key{code: code, kind: "press"} when code in ["up", "k"] ->
        loop(terminal, move_selection(state, -1))

      %Event.Key{code: code, kind: "press"} when code in ["down", "j"] ->
        loop(terminal, move_selection(state, 1))

      %Event.Key{code: code, kind: "press"}
      when code in ["enter", " "] and state.focus == :tasks ->
        loop(terminal, toggle_task_status(state))

      %Event.Key{code: "n", kind: "press"} when state.focus == :tasks ->
        loop(terminal, %{state | input_mode: :new_task, tick: state.tick + 1})

      %Event.Key{code: "d", kind: "press"} when state.focus == :tasks ->
        loop(terminal, delete_task(state))

      _ ->
        loop(terminal, %{state | tick: state.tick + 1})
    end
  end

  defp header_widget(state) do
    titles =
      Enum.map(@team, fn name ->
        tasks = Map.get(state.boards, name, [])
        done = Enum.count(tasks, &(&1.status == "Done"))
        total = length(tasks)
        "#{name} (#{done}/#{total})"
      end)

    %Tabs{
      titles: titles,
      selected: state.team_selected,
      style: %Style{fg: :dark_gray},
      highlight_style: %Style{fg: :cyan, modifiers: [:bold]},
      divider: " │ ",
      block: %Block{
        title: " ExRatatui Task Tracker ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  defp team_widget(state) do
    focused = state.focus == :team

    items =
      Enum.map(@team, fn name ->
        tasks = Map.get(state.boards, name, [])
        done = Enum.count(tasks, &(&1.status == "Done"))
        total = length(tasks)
        "#{name} (#{done}/#{total})"
      end)

    %List{
      items: items,
      highlight_style: %Style{
        fg: if(focused, do: :yellow, else: :cyan),
        modifiers: if(focused, do: [:bold], else: [])
      },
      highlight_symbol: if(focused, do: " ▸ ", else: " ▸ "),
      selected: state.team_selected,
      block: %Block{
        title: " Team #{if(focused, do: "●", else: "○")} ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: if(focused, do: :cyan, else: :dark_gray)}
      }
    }
  end

  defp tasks_widget(state) do
    focused = state.focus == :tasks
    tasks = current_tasks(state)
    member = current_member(state)

    rows =
      Enum.map(tasks, fn task ->
        status_display = status_icon(task.status) <> " " <> task.status
        [task.id, task.name, status_display]
      end)

    title = " #{member}'s Tasks #{if(focused, do: "●", else: "○")} [#{length(tasks)}] "

    %Table{
      rows: rows,
      header: ["ID", "Task", "Status"],
      widths: [{:length, 8}, {:min, 10}, {:length, 16}],
      highlight_style: %Style{
        fg: if(focused, do: :yellow, else: :dark_gray),
        modifiers: if(focused, do: [:bold], else: [])
      },
      highlight_symbol: if(focused, do: " ▸ ", else: "   "),
      selected: if(length(tasks) > 0, do: state.task_selected, else: nil),
      column_spacing: 2,
      block: %Block{
        title: title,
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: if(focused, do: :cyan, else: :dark_gray)}
      }
    }
  end

  defp scrollbar_widget(tasks, selected, visible_rows) do
    total = length(tasks)

    %Scrollbar{
      content_length: max(total, 1),
      position: selected,
      viewport_content_length: visible_rows,
      thumb_style: %Style{fg: :cyan},
      track_style: %Style{fg: :dark_gray}
    }
  end

  defp text_input_widget(state) do
    %TextInput{
      state: state.text_input,
      style: %Style{fg: :white},
      cursor_style: %Style{fg: :black, bg: :white},
      placeholder: "Enter task name...",
      placeholder_style: %Style{fg: :dark_gray},
      block: %Block{
        title: " New Task (Enter = confirm, Esc = cancel) ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :yellow}
      }
    }
  end

  defp gauge_widget(state) do
    tasks = current_tasks(state)
    done = Enum.count(tasks, &(&1.status == "Done"))
    total = length(tasks)
    ratio = if total > 0, do: done / total, else: 0.0
    member = current_member(state)

    %LineGauge{
      ratio: ratio,
      label: "#{member}: #{done}/#{total} tasks done",
      filled_style: %Style{fg: :green},
      unfilled_style: %Style{fg: :dark_gray}
    }
  end

  defp status_widget(state) do
    text =
      if state.input_mode == :new_task do
        " Type task name, Enter to confirm, Esc to cancel"
      else
        panel = state.focus |> Atom.to_string() |> String.capitalize()

        " Tab: switch │ ↑/k ↓/j: navigate │ Enter: toggle status │ n: new │ d: delete │ q: quit │ Focus: #{panel}"
      end

    %Paragraph{
      text: text,
      style: %Style{fg: :dark_gray},
      block: %Block{
        borders: [:top],
        border_style: %Style{fg: :dark_gray}
      }
    }
  end

  defp status_icon("Done"), do: "✓"
  defp status_icon("In Progress"), do: "◐"
  defp status_icon("Todo"), do: "○"
  defp status_icon(_), do: "?"

  defp next_panel(current) do
    idx = Enum.find_index(@panels, &(&1 == current))
    Enum.at(@panels, rem(idx + 1, length(@panels)))
  end

  defp move_selection(state, delta) do
    case state.focus do
      :team ->
        new = (state.team_selected + delta) |> max(0) |> min(length(@team) - 1)
        # Reset task selection when switching members
        tasks = Map.get(state.boards, Enum.at(@team, new), [])
        task_sel = min(state.task_selected, max(length(tasks) - 1, 0))
        %{state | team_selected: new, task_selected: task_sel, tick: state.tick + 1}

      :tasks ->
        tasks = current_tasks(state)
        max_idx = max(length(tasks) - 1, 0)
        new = (state.task_selected + delta) |> max(0) |> min(max_idx)
        %{state | task_selected: new, tick: state.tick + 1}
    end
  end

  defp toggle_task_status(state) do
    tasks = current_tasks(state)
    idx = state.task_selected

    if idx < length(tasks) do
      task = Enum.at(tasks, idx)
      updated = %{task | status: next_status(task.status)}
      new_tasks = Elixir.List.replace_at(tasks, idx, updated)
      update_board(state, new_tasks) |> Map.put(:tick, state.tick + 1)
    else
      state
    end
  end

  defp next_status("Todo"), do: "In Progress"
  defp next_status("In Progress"), do: "Done"
  defp next_status("Done"), do: "Todo"
  defp next_status(_), do: "Todo"

  defp create_task(state) do
    name = ExRatatui.text_input_get_value(state.text_input) |> String.trim()

    if name == "" do
      state
    else
      id = "EX-#{state.next_id}"
      new_task = %{id: id, name: name, status: "Todo"}
      tasks = current_tasks(state) ++ [new_task]
      state = update_board(state, tasks)
      %{state | next_id: state.next_id + 1, task_selected: length(tasks) - 1}
    end
  end

  defp delete_task(state) do
    tasks = current_tasks(state)
    idx = state.task_selected

    if idx < length(tasks) and length(tasks) > 0 do
      new_tasks = Elixir.List.delete_at(tasks, idx)
      new_selected = min(idx, max(length(new_tasks) - 1, 0))
      state = update_board(state, new_tasks)
      %{state | task_selected: new_selected, tick: state.tick + 1}
    else
      state
    end
  end
end

TaskTracker.run()
