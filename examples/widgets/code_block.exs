# Example: interactive CodeBlock viewer — cycle themes and toggle line
# numbers / line emphasis to compare how a snippet looks across the seven
# bundled syntect themes.
#
# Run with:
#   mix run examples/widgets/code_block.exs
#
# Controls:
#   t — cycle theme       (base16-ocean-dark / -light / eighties-dark / mocha-dark
#                          / inspired-github / solarized-dark / -light)
#   l — cycle language    (rust / python / ruby / javascript / json)
#   n — toggle line numbers
#   h — toggle emphasis on lines 3..5
#   q — quit

alias ExRatatui.Event
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, CodeBlock, Paragraph}

defmodule CodeBlockDemo do
  use ExRatatui.App

  @themes [
    :base16_ocean_dark,
    :base16_ocean_light,
    :base16_eighties_dark,
    :base16_mocha_dark,
    :inspired_github,
    :solarized_dark,
    :solarized_light
  ]

  @samples [
    {"rust",
     """
     fn fib(n: u32) -> u32 {
         match n {
             0 | 1 => n,
             _ => fib(n - 1) + fib(n - 2),
         }
     }
     """},
    {"python",
     """
     def fib(n):
         if n < 2:
             return n
         return fib(n - 1) + fib(n - 2)
     """},
    {"ruby",
     """
     def fib(n)
       n < 2 ? n : fib(n - 1) + fib(n - 2)
     end
     """},
    {"javascript",
     """
     function fib(n) {
       if (n < 2) return n;
       return fib(n - 1) + fib(n - 2);
     }
     """},
    {"json",
     """
     {
       "name": "ex_ratatui",
       "version": "0.9.0",
       "features": ["code_block", "big_text"]
     }
     """},
    {"elixir",
     """
     defmodule Fib do
       @doc "Compute the nth fibonacci number."
       def of(n) when n < 2, do: n
       def of(n), do: of(n - 1) + of(n - 2)
     end
     """}
  ]

  @impl true
  def mount(_opts) do
    {:ok,
     %{
       theme: hd(@themes),
       sample_idx: 0,
       line_numbers: true,
       emphasis: false
     }}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [code_area, status_area, help_area] =
      Layout.split(area, :vertical, [{:min, 0}, {:length, 3}, {:length, 3}])

    {language, source} = Enum.at(@samples, state.sample_idx)

    code = %CodeBlock{
      content: source,
      language: language,
      theme: state.theme,
      line_numbers: state.line_numbers,
      highlight_lines: if(state.emphasis, do: [3..5], else: []),
      block: %Block{
        title: " #{language} · #{state.theme} ",
        borders: [:all],
        border_type: :rounded,
        border_style: %Style{fg: :dark_gray}
      }
    }

    status = %Paragraph{
      text: status_text(state, language),
      style: %Style{fg: :light_cyan, modifiers: [:bold]},
      block: %Block{borders: [:all], border_type: :rounded, title: " status "}
    }

    help = %Paragraph{
      text: "  t = theme   l = language   n = line numbers   h = emphasis   q = quit",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:top], border_style: %Style{fg: :dark_gray}}
    }

    [
      {code, code_area},
      {status, status_area},
      {help, help_area}
    ]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: "t", kind: "press"}, state) do
    {:noreply, %{state | theme: cycle(@themes, state.theme)}}
  end

  def handle_event(%Event.Key{code: "l", kind: "press"}, state) do
    {:noreply, %{state | sample_idx: rem(state.sample_idx + 1, length(@samples))}}
  end

  def handle_event(%Event.Key{code: "n", kind: "press"}, state) do
    {:noreply, %{state | line_numbers: !state.line_numbers}}
  end

  def handle_event(%Event.Key{code: "h", kind: "press"}, state) do
    {:noreply, %{state | emphasis: !state.emphasis}}
  end

  def handle_event(_event, state), do: {:noreply, state}

  defp cycle(options, current) do
    idx = Enum.find_index(options, &(&1 == current)) || 0
    Enum.at(options, rem(idx + 1, length(options)))
  end

  defp status_text(state, language) do
    """
      theme: #{state.theme}   language: #{language}
      line_numbers: #{state.line_numbers}   emphasis: #{state.emphasis}\
    """
  end
end

{:ok, pid} = CodeBlockDemo.start_link([])

ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
