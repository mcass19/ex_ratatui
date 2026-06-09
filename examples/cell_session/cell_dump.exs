# Example: render a small TUI into a CellSession and inspect the cells
# as plain Elixir data.
#
# `ExRatatui.CellSession` gives you cells as structured data. This script
# shows the simplest possible consumer of cells: walk the snapshot,
# print the symbol grid as plain text.
#
# Run with: mix run examples/cell_session/cell_dump.exs

alias ExRatatui.CellSession
alias ExRatatui.CellSession.Snapshot
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.Block
alias ExRatatui.Widgets.Paragraph

session = CellSession.new(40, 6)

paragraph = %Paragraph{
  text: "Hello from CellSession!\nNo terminal needed — just data.",
  style: %Style{fg: :light_cyan, modifiers: [:bold]},
  alignment: :center,
  block: %Block{
    title: " cell_dump ",
    borders: [:all],
    border_type: :rounded
  }
}

:ok = CellSession.draw(session, [{paragraph, %Rect{x: 0, y: 0, width: 40, height: 6}}])

%Snapshot{width: w, height: _h, cells: cells} = CellSession.take_cells(session)
:ok = CellSession.close(session)

cells
|> Enum.chunk_every(w)
|> Enum.each(fn row ->
  row |> Enum.map_join(& &1.symbol) |> IO.puts()
end)

IO.puts("\nSee: https://hexdocs.pm/ex_ratatui/cell_session.html")
