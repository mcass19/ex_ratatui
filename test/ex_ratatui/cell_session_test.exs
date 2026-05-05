defmodule ExRatatui.CellSessionTest do
  use ExUnit.Case, async: true

  doctest ExRatatui.CellSession
  doctest ExRatatui.CellSession.Cell
  doctest ExRatatui.CellSession.Snapshot
  doctest ExRatatui.CellSession.Diff

  alias ExRatatui.Bridge
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native
  alias ExRatatui.Style
  alias ExRatatui.Widgets.Paragraph

  # ----------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------

  # Render a single styled symbol at column 0 of a fresh 1-row session
  # and return the raw cell tuple from a take_cells snapshot. Goes
  # through Bridge.encode_commands! so the wire shape (Line/Span text
  # encoding, etc.) matches what the rest of the project produces, then
  # uses the Native NIF directly so the tuple is returned verbatim
  # (which is what these encoder-fidelity tests want to assert against).
  defp paint_cell(symbol, %Style{} = style) do
    paragraph = %Paragraph{text: symbol, style: style}
    rect = %Rect{x: 0, y: 0, width: 5, height: 1}
    commands = Bridge.encode_commands!([{paragraph, rect}])

    ref = Native.cell_session_new(5, 1)
    :ok = Native.cell_session_draw(ref, commands)
    %{cells: cells} = Native.cell_session_take_cells(ref)
    :ok = Native.cell_session_close(ref)

    Enum.find(cells, fn {x, _y, sym, _fg, _bg, _mods, _skip} ->
      x == 0 and sym == symbol
    end)
  end

  # Build the encoded command list for a single styled-paragraph draw.
  # Used by diff tests that need to drive specific styled content
  # through the NIF without going through the wrapper (so we can read
  # raw tuples back).
  defp paragraph_command(text, %Style{} = style, %Rect{} = rect) do
    paragraph = %Paragraph{text: text, style: style}
    Bridge.encode_commands!([{paragraph, rect}])
  end

  # ----------------------------------------------------------------------
  # cell_session_new/2
  # ----------------------------------------------------------------------

  describe "cell_session_new/2" do
    test "returns a reference for reasonable dimensions" do
      ref = Native.cell_session_new(80, 24)
      assert is_reference(ref)
      assert :ok = Native.cell_session_close(ref)
    end

    test "succeeds at a 1x1 minimum size" do
      ref = Native.cell_session_new(1, 1)
      assert is_reference(ref)
      assert :ok = Native.cell_session_close(ref)
    end

    test "independent sessions get distinct references" do
      a = Native.cell_session_new(80, 24)
      b = Native.cell_session_new(80, 24)

      assert is_reference(a)
      assert is_reference(b)
      assert a != b

      :ok = Native.cell_session_close(a)
      :ok = Native.cell_session_close(b)
    end
  end

  # ----------------------------------------------------------------------
  # cell_session_close/1
  # ----------------------------------------------------------------------

  describe "cell_session_close/1" do
    test "is idempotent" do
      ref = Native.cell_session_new(80, 24)
      assert :ok = Native.cell_session_close(ref)
      assert :ok = Native.cell_session_close(ref)
    end

    test "does not touch OS terminal state" do
      # Same guarantee SessionResource makes — creating and tearing
      # down many sessions in a test context must not enable raw mode
      # or otherwise touch the real tty.
      for _ <- 1..8 do
        ref = Native.cell_session_new(80, 24)
        assert :ok = Native.cell_session_close(ref)
      end
    end
  end

  # ----------------------------------------------------------------------
  # cell_session_draw/2
  # ----------------------------------------------------------------------

  describe "cell_session_draw/2" do
    test "draw with empty commands succeeds" do
      ref = Native.cell_session_new(20, 5)
      assert :ok = Native.cell_session_draw(ref, [])
      :ok = Native.cell_session_close(ref)
    end

    test "draw with a Clear widget round-trips through decoding" do
      ref = Native.cell_session_new(20, 5)
      commands = [{%{"type" => "clear"}, %{"x" => 0, "y" => 0, "width" => 20, "height" => 5}}]
      assert :ok = Native.cell_session_draw(ref, commands)
      :ok = Native.cell_session_close(ref)
    end

    test "draw rejects an unknown widget type" do
      ref = Native.cell_session_new(20, 5)

      commands = [
        {%{"type" => "not_a_widget"}, %{"x" => 0, "y" => 0, "width" => 5, "height" => 1}}
      ]

      assert {:error, _reason} = Native.cell_session_draw(ref, commands)
      :ok = Native.cell_session_close(ref)
    end

    test "draw on a closed session returns an error" do
      ref = Native.cell_session_new(20, 5)
      :ok = Native.cell_session_close(ref)
      assert {:error, reason} = Native.cell_session_draw(ref, [])
      assert reason =~ "closed"
    end
  end

  # ----------------------------------------------------------------------
  # cell_session_take_cells/1 — shape and dimensions
  # ----------------------------------------------------------------------

  describe "cell_session_take_cells/1 — shape" do
    test "returns a map with :width, :height, and :cells" do
      ref = Native.cell_session_new(10, 4)
      :ok = Native.cell_session_draw(ref, [])

      payload = Native.cell_session_take_cells(ref)
      assert %{width: 10, height: 4, cells: cells} = payload
      assert is_list(cells)

      :ok = Native.cell_session_close(ref)
    end

    test "cells count equals width * height" do
      ref = Native.cell_session_new(7, 3)
      :ok = Native.cell_session_draw(ref, [])

      %{cells: cells} = Native.cell_session_take_cells(ref)
      assert length(cells) == 7 * 3

      :ok = Native.cell_session_close(ref)
    end

    test "cells are emitted in row-major order with correct (col, row) coords" do
      ref = Native.cell_session_new(3, 2)
      :ok = Native.cell_session_draw(ref, [])

      %{cells: cells} = Native.cell_session_take_cells(ref)

      # Extract just the (col, row) pairs from each cell tuple.
      coords = Enum.map(cells, fn {x, y, _, _, _, _, _} -> {x, y} end)

      # Row-major order: (0,0), (1,0), (2,0), (0,1), (1,1), (2,1).
      assert coords == [{0, 0}, {1, 0}, {2, 0}, {0, 1}, {1, 1}, {2, 1}]

      :ok = Native.cell_session_close(ref)
    end

    test "default cells use :reset for fg/bg, empty modifiers, and skip: false" do
      ref = Native.cell_session_new(2, 1)
      :ok = Native.cell_session_draw(ref, [])

      %{cells: cells} = Native.cell_session_take_cells(ref)
      assert [{0, 0, " ", :reset, :reset, [], false}, _] = cells

      :ok = Native.cell_session_close(ref)
    end

    test "returns an error after close" do
      ref = Native.cell_session_new(20, 5)
      :ok = Native.cell_session_close(ref)

      assert {:error, reason} = Native.cell_session_take_cells(ref)
      assert reason =~ "closed"
    end
  end

  # ----------------------------------------------------------------------
  # Encoder fidelity: every supported color and modifier must round-trip
  # from Rust → Elixir through the take_cells path.
  #
  # These tests are the Elixir-level proof that the encoders in
  # `style.rs` produce values that match `ExRatatui.Style`'s vocabulary
  # exactly. They live here (rather than as a synthetic Term test)
  # because constructing a real `Env` from cargo is not ergonomic.
  # ----------------------------------------------------------------------

  describe "encoder fidelity — colors" do
    test "named colors round-trip as atoms" do
      # The 16 named non-reset colors must each round-trip as the
      # exact same atom. `:reset` is exercised separately below — it
      # IS the default fg value, so painting with `fg: :reset` produces
      # cells indistinguishable from any other unstyled cell.
      for color <- [
            :black,
            :red,
            :green,
            :yellow,
            :blue,
            :magenta,
            :cyan,
            :gray,
            :dark_gray,
            :light_red,
            :light_green,
            :light_yellow,
            :light_blue,
            :light_magenta,
            :light_cyan,
            :white
          ] do
        cell = paint_cell("X", %Style{fg: color})
        assert {0, 0, "X", ^color, :reset, [], false} = cell
      end
    end

    test "RGB colors round-trip as {:rgb, r, g, b} tuples" do
      cell = paint_cell("X", %Style{fg: {:rgb, 200, 100, 50}})
      assert {0, 0, "X", {:rgb, 200, 100, 50}, :reset, [], false} = cell
    end

    test "indexed colors round-trip as {:indexed, n} tuples" do
      cell = paint_cell("X", %Style{fg: {:indexed, 42}})
      assert {0, 0, "X", {:indexed, 42}, :reset, [], false} = cell
    end

    test "background colors round-trip on the :bg field" do
      cell = paint_cell("X", %Style{fg: :white, bg: :blue})
      assert {0, 0, "X", :white, :blue, [], false} = cell
    end

    test "default cells (no draw) carry :reset on both fg and bg" do
      # Verifies the encoder emits the :reset atom (not nil, not the
      # named color for the host terminal default) when the underlying
      # ratatui Color is Color::Reset.
      ref = Native.cell_session_new(2, 1)
      :ok = Native.cell_session_draw(ref, [])

      %{cells: [{0, 0, " ", :reset, :reset, [], false} | _]} =
        Native.cell_session_take_cells(ref)

      :ok = Native.cell_session_close(ref)
    end
  end

  describe "encoder fidelity — modifiers" do
    test "single modifier round-trips as a one-element atom list" do
      cell = paint_cell("X", %Style{modifiers: [:bold]})
      assert {0, 0, "X", _fg, _bg, [:bold], false} = cell
    end

    test "all six modifiers round-trip in a stable sorted order" do
      cell =
        paint_cell("X", %Style{
          modifiers: [:bold, :dim, :italic, :underlined, :crossed_out, :reversed]
        })

      # Encoder emits modifiers in ratatui's canonical bitflag order:
      # bold, dim, italic, underlined, crossed_out, reversed.
      assert {0, 0, "X", _fg, _bg, mods, false} = cell
      assert mods == [:bold, :dim, :italic, :underlined, :crossed_out, :reversed]
    end

    test "modifier list is sorted regardless of input order" do
      # Pass modifiers in reverse — the encoder normalises by walking
      # the bitflag in canonical order, so the output is stable.
      cell =
        paint_cell("X", %Style{
          modifiers: [:reversed, :crossed_out, :underlined, :italic, :dim, :bold]
        })

      assert {0, 0, "X", _fg, _bg, mods, false} = cell
      assert mods == [:bold, :dim, :italic, :underlined, :crossed_out, :reversed]
    end

    test "no modifiers produces an empty list" do
      cell = paint_cell("X", %Style{})
      assert {0, 0, "X", _fg, _bg, [], false} = cell
    end
  end

  # ----------------------------------------------------------------------
  # cell_session_take_cells_diff/1 — the streaming-deltas path
  # ----------------------------------------------------------------------

  describe "cell_session_take_cells_diff/1 — diff invariants" do
    test "first call returns the full grid as ops" do
      # No prior baseline → the diff must contain every cell so the
      # consumer can paint a complete initial picture.
      ref = Native.cell_session_new(4, 2)
      :ok = Native.cell_session_draw(ref, [])

      diff = Native.cell_session_take_cells_diff(ref)
      assert %{width: 4, height: 2, ops: ops} = diff
      assert length(ops) == 4 * 2

      :ok = Native.cell_session_close(ref)
    end

    test "second call with no intervening draw returns empty ops" do
      # Identical buffer → diff against itself → zero deltas.
      ref = Native.cell_session_new(4, 2)
      :ok = Native.cell_session_draw(ref, [])
      _full = Native.cell_session_take_cells_diff(ref)

      diff = Native.cell_session_take_cells_diff(ref)
      assert %{width: 4, height: 2, ops: []} = diff

      :ok = Native.cell_session_close(ref)
    end

    test "single-cell change returns a single op" do
      # First call seeds the baseline. Second call after a redraw that
      # touches one cell must surface only that cell. The Paragraph
      # rect is 1x1 on purpose: a wider rect would propagate the
      # `fg: :red` styling to every cell in the rect (even unpainted
      # space cells), and the diff would correctly report all of them.
      # That's a real ratatui behavior worth knowing — wrapping the
      # styled text in a tight rect is how a renderer keeps deltas
      # minimal.
      ref = Native.cell_session_new(5, 1)
      :ok = Native.cell_session_draw(ref, [])
      _full = Native.cell_session_take_cells_diff(ref)

      commands =
        paragraph_command("X", %Style{fg: :red}, %Rect{x: 0, y: 0, width: 1, height: 1})

      :ok = Native.cell_session_draw(ref, commands)

      diff = Native.cell_session_take_cells_diff(ref)
      assert %{ops: ops} = diff

      # Exactly one cell changed: (0, 0) became "X" red.
      assert [{0, 0, "X", :red, :reset, [], false}] = ops

      :ok = Native.cell_session_close(ref)
    end

    test "resize between diff calls returns the full grid as ops" do
      # The prior baseline at the old area is no longer comparable —
      # cell counts don't even match. We emit the full new grid so the
      # consumer can repaint from scratch.
      ref = Native.cell_session_new(3, 2)
      :ok = Native.cell_session_draw(ref, [])
      _full = Native.cell_session_take_cells_diff(ref)

      :ok = Native.cell_session_resize(ref, 5, 4)
      :ok = Native.cell_session_draw(ref, [])

      diff = Native.cell_session_take_cells_diff(ref)
      assert %{width: 5, height: 4, ops: ops} = diff
      assert length(ops) == 5 * 4

      :ok = Native.cell_session_close(ref)
    end

    test "take_cells does not affect the diff baseline" do
      # take_cells/1 is documented as stateless. A consumer must be able
      # to grab a snapshot mid-stream without disturbing the baseline
      # the next take_cells_diff/1 will compare against.
      ref = Native.cell_session_new(4, 1)
      :ok = Native.cell_session_draw(ref, [])
      _full = Native.cell_session_take_cells_diff(ref)

      # Read a snapshot — must not touch prev_buffer.
      _snapshot = Native.cell_session_take_cells(ref)

      # Next diff call should still see "no change" relative to the
      # previous diff baseline.
      diff = Native.cell_session_take_cells_diff(ref)
      assert %{ops: []} = diff

      :ok = Native.cell_session_close(ref)
    end

    test "two consecutive diffs after the same draw show only the delta from the first to the second" do
      # Build up a small four-frame sequence: bg, "A", "B", "B" again.
      # Each diff captures only what changed since the LAST diff call.
      ref = Native.cell_session_new(3, 1)
      rect = %Rect{x: 0, y: 0, width: 3, height: 1}

      :ok = Native.cell_session_draw(ref, [])
      first = Native.cell_session_take_cells_diff(ref)
      assert length(first.ops) == 3

      :ok = Native.cell_session_draw(ref, paragraph_command("A", %Style{}, rect))
      second = Native.cell_session_take_cells_diff(ref)
      assert [{0, 0, "A", :reset, :reset, [], false}] = second.ops

      :ok = Native.cell_session_draw(ref, paragraph_command("B", %Style{}, rect))
      third = Native.cell_session_take_cells_diff(ref)
      assert [{0, 0, "B", :reset, :reset, [], false}] = third.ops

      # No intervening draw — empty diff.
      fourth = Native.cell_session_take_cells_diff(ref)
      assert fourth.ops == []

      :ok = Native.cell_session_close(ref)
    end

    test "returns an error after close" do
      ref = Native.cell_session_new(20, 5)
      :ok = Native.cell_session_close(ref)

      assert {:error, reason} = Native.cell_session_take_cells_diff(ref)
      assert reason =~ "closed"
    end

    test "close+reopen wipes the baseline (next diff returns full)" do
      # close clears prev_buffer, but a CellSession ref points at one
      # specific resource — once closed it cannot be reopened. The
      # equivalent flow is: close, construct a new session, first diff
      # call returns the full grid (covered by the very first test in
      # this describe block). This test pins the behavior end-to-end.
      ref = Native.cell_session_new(2, 1)
      :ok = Native.cell_session_draw(ref, [])
      _ = Native.cell_session_take_cells_diff(ref)
      :ok = Native.cell_session_close(ref)

      ref2 = Native.cell_session_new(2, 1)
      :ok = Native.cell_session_draw(ref2, [])
      diff = Native.cell_session_take_cells_diff(ref2)
      assert length(diff.ops) == 2

      :ok = Native.cell_session_close(ref2)
    end
  end

  # ----------------------------------------------------------------------
  # cell_session_feed_input/2 — input parsing parity with Session
  # ----------------------------------------------------------------------

  describe "cell_session_feed_input/2" do
    test "parses a plain ASCII keystroke into a key event" do
      ref = Native.cell_session_new(20, 5)
      assert [{:key, "a", [], "press"}] = Native.cell_session_feed_input(ref, "a")
      :ok = Native.cell_session_close(ref)
    end

    test "parses CSI arrow keys" do
      ref = Native.cell_session_new(20, 5)
      assert [{:key, "up", [], "press"}] = Native.cell_session_feed_input(ref, "\e[A")
      :ok = Native.cell_session_close(ref)
    end

    test "buffers a partial escape sequence across calls" do
      ref = Native.cell_session_new(20, 5)
      assert [] = Native.cell_session_feed_input(ref, "\e")
      assert [] = Native.cell_session_feed_input(ref, "[")
      assert [{:key, "up", [], "press"}] = Native.cell_session_feed_input(ref, "A")
      :ok = Native.cell_session_close(ref)
    end

    test "still parses input after the session has been closed" do
      ref = Native.cell_session_new(20, 5)
      :ok = Native.cell_session_close(ref)
      assert [{:key, "a", [], "press"}] = Native.cell_session_feed_input(ref, "a")
    end
  end

  # ----------------------------------------------------------------------
  # cell_session_resize/3 and cell_session_size/1
  # ----------------------------------------------------------------------

  describe "cell_session_resize/3 and cell_session_size/1" do
    test "size returns the dimensions construction was done with" do
      ref = Native.cell_session_new(80, 24)
      assert {80, 24} = Native.cell_session_size(ref)
      :ok = Native.cell_session_close(ref)
    end

    test "resize updates the size and the next take_cells reports new dimensions" do
      ref = Native.cell_session_new(20, 5)
      :ok = Native.cell_session_resize(ref, 100, 30)
      assert {100, 30} = Native.cell_session_size(ref)

      :ok = Native.cell_session_draw(ref, [])
      %{width: 100, height: 30} = Native.cell_session_take_cells(ref)

      :ok = Native.cell_session_close(ref)
    end

    test "resize on a closed session returns an error" do
      ref = Native.cell_session_new(20, 5)
      :ok = Native.cell_session_close(ref)
      assert {:error, reason} = Native.cell_session_resize(ref, 40, 10)
      assert reason =~ "closed"
    end
  end

  # ----------------------------------------------------------------------
  # ExRatatui.CellSession (Elixir wrapper)
  # ----------------------------------------------------------------------

  describe "ExRatatui.CellSession (Elixir wrapper)" do
    alias ExRatatui.CellSession
    alias ExRatatui.CellSession.{Cell, Diff, Snapshot}
    alias ExRatatui.Event
    alias ExRatatui.Layout.Rect
    alias ExRatatui.Style
    alias ExRatatui.Widgets.Paragraph

    test "new/2 returns a CellSession struct holding a reference" do
      session = CellSession.new(80, 24)

      assert %CellSession{ref: ref} = session
      assert is_reference(ref)
      assert {80, 24} = CellSession.size(session)

      :ok = CellSession.close(session)
    end

    test "draw/2 accepts widget structs and renders into the buffer" do
      session = CellSession.new(20, 5)
      widgets = [{%Paragraph{text: "hi"}, %Rect{x: 0, y: 0, width: 20, height: 5}}]
      assert :ok = CellSession.draw(session, widgets)
      :ok = CellSession.close(session)
    end

    test "take_cells/1 returns a Snapshot of Cell structs" do
      session = CellSession.new(3, 1)
      :ok = CellSession.draw(session, [])

      assert %Snapshot{width: 3, height: 1, cells: cells} = CellSession.take_cells(session)
      assert length(cells) == 3
      assert Enum.all?(cells, &match?(%Cell{}, &1))

      # Default cells: " ", :reset, :reset, [], false.
      assert [
               %Cell{
                 row: 0,
                 col: 0,
                 symbol: " ",
                 fg: :reset,
                 bg: :reset,
                 modifiers: [],
                 skip: false
               }
               | _
             ] = cells

      :ok = CellSession.close(session)
    end

    test "take_cells/1 reflects styled paragraph content" do
      session = CellSession.new(5, 1)

      paragraph = %Paragraph{
        text: "X",
        style: %Style{fg: :red, modifiers: [:bold]}
      }

      :ok = CellSession.draw(session, [{paragraph, %Rect{x: 0, y: 0, width: 5, height: 1}}])

      %Snapshot{cells: cells} = CellSession.take_cells(session)
      x_cell = Enum.find(cells, &(&1.symbol == "X"))

      assert %Cell{row: 0, col: 0, symbol: "X", fg: :red, modifiers: [:bold]} = x_cell

      :ok = CellSession.close(session)
    end

    test "take_cells_diff/1 returns a Diff of Cell structs in :ops" do
      session = CellSession.new(3, 1)
      :ok = CellSession.draw(session, [])

      assert %Diff{width: 3, height: 1, ops: ops} = CellSession.take_cells_diff(session)
      assert length(ops) == 3
      assert Enum.all?(ops, &match?(%Cell{}, &1))

      # Second call with no draw → no ops.
      assert %Diff{ops: []} = CellSession.take_cells_diff(session)

      :ok = CellSession.close(session)
    end

    test "feed_input/2 returns decoded Event structs" do
      session = CellSession.new(20, 5)

      assert [%Event.Key{code: "a", modifiers: [], kind: "press"}] =
               CellSession.feed_input(session, "a")

      :ok = CellSession.close(session)
    end

    test "feed_input/2 buffers a partial CSI across calls" do
      session = CellSession.new(20, 5)

      assert [] = CellSession.feed_input(session, "\e")
      assert [] = CellSession.feed_input(session, "[")

      assert [%Event.Key{code: "up", modifiers: [], kind: "press"}] =
               CellSession.feed_input(session, "A")

      :ok = CellSession.close(session)
    end

    test "feed_input/2 still works after close/1" do
      session = CellSession.new(20, 5)
      :ok = CellSession.close(session)
      assert [%Event.Key{code: "x"}] = CellSession.feed_input(session, "x")
    end

    test "resize/3 updates the cached size" do
      session = CellSession.new(20, 5)
      assert :ok = CellSession.resize(session, 100, 30)
      assert {100, 30} = CellSession.size(session)
      :ok = CellSession.close(session)
    end

    test "draw/2 on a closed session returns an error tuple" do
      session = CellSession.new(20, 5)
      :ok = CellSession.close(session)
      assert {:error, reason} = CellSession.draw(session, [])
      assert reason =~ "closed"
    end

    test "take_cells/1 on a closed session returns an error tuple" do
      session = CellSession.new(20, 5)
      :ok = CellSession.close(session)
      assert {:error, reason} = CellSession.take_cells(session)
      assert reason =~ "closed"
    end

    test "take_cells_diff/1 on a closed session returns an error tuple" do
      session = CellSession.new(20, 5)
      :ok = CellSession.close(session)
      assert {:error, reason} = CellSession.take_cells_diff(session)
      assert reason =~ "closed"
    end

    test "reset_parser/1 discards a buffered partial escape sequence" do
      session = CellSession.new(20, 5)
      assert [] = CellSession.feed_input(session, "\e")
      assert :ok = CellSession.reset_parser(session)

      assert [%Event.Key{code: "a", modifiers: [], kind: "press"}] =
               CellSession.feed_input(session, "a")

      :ok = CellSession.close(session)
    end

    test "close/1 is idempotent" do
      session = CellSession.new(20, 5)
      assert :ok = CellSession.close(session)
      assert :ok = CellSession.close(session)
    end

    test "concurrent sessions are independent" do
      a = CellSession.new(20, 5)
      b = CellSession.new(40, 10)

      :ok = CellSession.draw(a, [])
      :ok = CellSession.draw(b, [])

      assert %Snapshot{width: 20, height: 5} = CellSession.take_cells(a)
      assert %Snapshot{width: 40, height: 10} = CellSession.take_cells(b)

      :ok = CellSession.resize(a, 100, 30)
      assert {100, 30} = CellSession.size(a)
      assert {40, 10} = CellSession.size(b)

      :ok = CellSession.close(a)
      :ok = CellSession.close(b)
    end
  end
end
