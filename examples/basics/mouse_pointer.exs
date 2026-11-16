# Example: buttons that react to the mouse, with a hand pointer over them.
# Run with: EX_RATATUI_POINTER=1 mix run examples/basics/mouse_pointer.exs
#      or:  EX_RATATUI_POINTER=1 mix run --no-halt examples/basics/mouse_pointer.exs --ssh
#           then: ssh demo@localhost -p 2222   (password: demo)
#      or:  EX_RATATUI_POINTER=1 elixir --sname app --cookie demo -S mix run --no-halt \
#             examples/basics/mouse_pointer.exs --distributed
#           then, from `iex --sname local --cookie demo -S mix`:
#             ExRatatui.Distributed.attach(:"app@hostname", MousePointerDemo, mouse_capture: true)
#
# Controls: hover and click the buttons; q = quit
#
# Hovering a button lights it up and, through the `pointer:` runtime opt,
# turns the mouse pointer into a hand (a "not allowed" sign over the locked
# one), the way a web page does. The opt goes out on every mouse move: the
# runtime only writes to the terminal when the shape changes, and the frame
# is only redrawn when the hovered button changes.
#
# Nothing detects whether a terminal understands pointer shapes (kitty and
# Ghostty do), so the app decides: here EX_RATATUI_POINTER=1 is that
# decision. Without it the buttons still light up and the pointer stays as
# it is. The pointer that changes is the one of the terminal the app is
# drawn on: over SSH or an attach that is the client's, not this node's.

alias ExRatatui.Event.{Key, Mouse}
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Paragraph}

defmodule MousePointerDemo do
  use ExRatatui.App

  @card %Rect{x: 1, y: 0, width: 48, height: 12}

  @buttons [
    {:save, "Save", %Rect{x: 4, y: 2, width: 12, height: 3}},
    {:deploy, "Deploy", %Rect{x: 18, y: 2, width: 12, height: 3}},
    {:locked, "Locked", %Rect{x: 32, y: 2, width: 12, height: 3}}
  ]

  @status %Rect{x: 4, y: 6, width: 42, height: 4}

  @impl true
  def mount(_opts) do
    {:ok, %{pointer?: System.get_env("EX_RATATUI_POINTER") == "1", hover: nil, clicked: nil}}
  end

  @impl true
  def render(state, _frame) do
    card = %Block{title: " mouse pointer ", borders: [:all], border_type: :rounded}
    status = %Paragraph{text: status_text(state), style: %Style{fg: :dark_gray}}

    buttons = for {id, label, rect} <- @buttons, do: {button(id, label, state.hover == id), rect}

    [{card, @card}, {status, @status}] ++ buttons
  end

  @impl true
  def handle_event(%Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Mouse{kind: kind, x: x, y: y}, state) when kind in ["moved", "drag"] do
    hover = button_at(x, y)
    opts = [render?: hover != state.hover] ++ pointer_opt(state, hover)
    {:noreply, %{state | hover: hover}, opts}
  end

  def handle_event(%Mouse{kind: "down", button: "left", x: x, y: y}, state) do
    case button_at(x, y) do
      id when id in [:save, :deploy] -> {:noreply, %{state | clicked: id}}
      _ -> {:noreply, state, render?: false}
    end
  end

  def handle_event(_event, state), do: {:noreply, state, render?: false}

  # The same rectangles drive rendering and hit-testing.
  defp button_at(x, y) do
    Enum.find_value(@buttons, fn {id, _label, rect} ->
      if x in rect.x..(rect.x + rect.width - 1) and y in rect.y..(rect.y + rect.height - 1),
        do: id
    end)
  end

  defp pointer_opt(%{pointer?: false}, _hover), do: []
  defp pointer_opt(_state, nil), do: [pointer: :default]
  defp pointer_opt(_state, :locked), do: [pointer: :not_allowed]
  defp pointer_opt(_state, _button), do: [pointer: :pointer]

  defp button(id, label, hovered?) do
    {text, border} = button_styles(id, hovered?)

    %Paragraph{
      text: label,
      alignment: :center,
      style: text,
      block: %Block{borders: [:all], border_type: :rounded, border_style: border, style: text}
    }
  end

  defp button_styles(:locked, false), do: {%Style{fg: :dark_gray}, %Style{fg: :dark_gray}}
  defp button_styles(:locked, true), do: {%Style{fg: :dark_gray}, %Style{fg: :red}}
  defp button_styles(_id, false), do: {%Style{fg: :white}, %Style{fg: :cyan}}

  defp button_styles(_id, true) do
    lit = %Style{fg: :black, bg: :cyan, modifiers: [:bold]}
    {lit, lit}
  end

  defp status_text(state) do
    """
    Last click: #{clicked(state.clicked)}
    Pointer shapes: #{pointer_shapes(state.pointer?)}

    Hover and click the buttons. q quits.
    """
  end

  defp clicked(nil), do: "none yet"
  defp clicked(:save), do: "Save"
  defp clicked(:deploy), do: "Deploy"

  defp pointer_shapes(true), do: "on"
  defp pointer_shapes(false), do: "off (EX_RATATUI_POINTER=1)"
end

# Each mode starts one process; the script then waits for it to stop. The
# daemon and the listener are linked to this script, so letting it finish
# would take them down with it.
{:ok, pid} =
  case System.argv() do
    ["--ssh" | _] ->
      {:ok, daemon} =
        ExRatatui.SSH.Daemon.start_link(
          mod: MousePointerDemo,
          name: nil,
          port: 2222,
          system_dir:
            ExRatatui.SSH.Daemon.ensure_host_key!(
              Path.join(System.tmp_dir!(), "ex_ratatui_example_host_keys")
            ),
          auth_methods: ~c"password",
          user_passwords: [{~c"demo", ~c"demo"}],
          app_opts: [mouse_capture: true]
        )

      IO.puts("ssh demo@localhost -p 2222   (password: demo) — Ctrl-C twice stops the daemon")
      {:ok, daemon}

    ["--distributed" | _] ->
      if not Node.alive?() do
        IO.puts(
          :stderr,
          "Start this node with --sname (or --name) and a --cookie to attach to it."
        )

        System.halt(1)
      end

      {:ok, listener} = ExRatatui.Distributed.Listener.start_link(mod: MousePointerDemo)

      IO.puts("""
      From another node with the same cookie:

          ExRatatui.Distributed.attach(#{inspect(Node.self())}, MousePointerDemo, mouse_capture: true)

      Ctrl-C twice stops this node.
      """)

      {:ok, listener}

    _ ->
      # Start the app directly (not supervised, since this is a script)
      MousePointerDemo.start_link(name: nil, mouse_capture: true)
  end

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
