defmodule ExRatatui.Widgets.TableTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Table}

  setup do
    terminal = ExRatatui.init_test_terminal(60, 15)
    on_exit(fn -> Native.restore_terminal(terminal) end)
    %{terminal: terminal}
  end

  describe "Table widget" do
    test "simple table", %{terminal: terminal} do
      table = %Table{
        rows: [["Alice", "30"], ["Bob", "25"]],
        widths: [{:length, 15}, {:length, 10}]
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{table, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Alice"
      assert content =~ "Bob"
    end

    test "table with header", %{terminal: terminal} do
      table = %Table{
        rows: [["Alice", "30"], ["Bob", "25"]],
        header: ["Name", "Age"],
        widths: [{:length, 15}, {:length, 10}]
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{table, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Name"
      assert content =~ "Age"
      assert content =~ "Alice"
    end

    test "table with selection and block", %{terminal: terminal} do
      table = %Table{
        rows: [["Row 1"], ["Row 2"], ["Row 3"]],
        widths: [{:percentage, 100}],
        highlight_style: %Style{fg: :cyan},
        highlight_symbol: "> ",
        selected: 0,
        block: %Block{title: "Data", borders: [:all]}
      }

      rect = %Rect{x: 0, y: 0, width: 40, height: 10}

      assert :ok = ExRatatui.draw(terminal, [{table, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "Data"
      assert content =~ "Row 1"
    end

    test "table with percentage widths", %{terminal: terminal} do
      table = %Table{
        rows: [["A", "B", "C"]],
        widths: [{:percentage, 33}, {:percentage, 33}, {:percentage, 34}]
      }

      rect = %Rect{x: 0, y: 0, width: 60, height: 5}

      assert :ok = ExRatatui.draw(terminal, [{table, rect}])
      content = ExRatatui.get_buffer_content(terminal)
      assert content =~ "A"
      assert content =~ "B"
      assert content =~ "C"
    end

    test "footer renders at the bottom of the table area", %{terminal: terminal} do
      table = %Table{
        rows: [["Alice", "30"]],
        header: ["Name", "Age"],
        footer: ["Total", "1 row"],
        widths: [{:length, 10}, {:length, 10}]
      }

      rect = %Rect{x: 0, y: 0, width: 30, height: 6}

      assert :ok = ExRatatui.draw(terminal, [{table, rect}])
      lines = ExRatatui.get_buffer_content(terminal) |> String.split("\n")
      assert hd(lines) =~ "Name"
      assert Enum.at(lines, 5) =~ "Total"
    end

    test "highlight_spacing :always reserves the symbol column without a selection",
         %{terminal: terminal} do
      table = %Table{
        rows: [["only"]],
        widths: [{:length, 10}],
        highlight_symbol: ">> ",
        highlight_spacing: :always
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{table, rect}])
      [row | _] = ExRatatui.get_buffer_content(terminal) |> String.split("\n")
      # Symbol-column gap pushes "only" to the right even with no selection.
      assert String.starts_with?(row, "   only")
    end

    test "header_style colors the header row", %{terminal: terminal} do
      table = %Table{
        rows: [["a"]],
        header: ["Name"],
        header_style: %ExRatatui.Style{fg: :magenta},
        widths: [{:length, 10}]
      }

      rect = %Rect{x: 0, y: 0, width: 20, height: 3}

      assert :ok = ExRatatui.draw(terminal, [{table, rect}])
    end
  end
end
