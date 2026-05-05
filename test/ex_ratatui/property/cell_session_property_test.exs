defmodule ExRatatui.Property.CellSessionPropertyTest do
  @moduledoc """
  Property-based invariants for `ExRatatui.CellSession`.

  These tests prove structural properties that hold across the input
  space rather than at hand-picked points. They cover:

    * conversion round-trips (`Cell.from_tuple/1`,
      `Snapshot.from_native/1`, `Diff.from_native/1`)
    * shape invariants of the NIF payloads (cell count = width × height,
      ops ⊆ snapshot cells)
    * encoder fidelity for arbitrary colors and modifier subsets
    * diff stability (no-op draw → empty diff)
    * modifier order normalisation independent of input order

  Reusable widget plumbing (`Bridge.encode_commands!`,
  `ExRatatui.Widgets.Paragraph`) is the same the example-based tests
  use, so a regression in either path will break here too.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExRatatui.Bridge
  alias ExRatatui.CellSession
  alias ExRatatui.CellSession.{Cell, Diff, Snapshot}
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native
  alias ExRatatui.Style
  alias ExRatatui.Widgets.Paragraph

  @named_colors ~w(
    black red green yellow blue magenta cyan gray
    dark_gray light_red light_green light_yellow light_blue
    light_magenta light_cyan white reset
  )a

  @canonical_modifier_order ~w(bold dim italic underlined crossed_out reversed)a

  # ----------------------------------------------------------------------
  # Generators
  # ----------------------------------------------------------------------

  # Colors as they appear inside a `%Style{}` — atoms for named colors,
  # tagged tuples for RGB/indexed. Excludes `:reset` because painting
  # with `:reset` is indistinguishable from painting unstyled (both
  # leave the cell at the default), which makes equality assertions
  # ambiguous.
  defp paint_color_gen do
    one_of([
      member_of(@named_colors -- [:reset]),
      gen all(r <- integer(0..255), g <- integer(0..255), b <- integer(0..255)) do
        {:rgb, r, g, b}
      end,
      gen all(i <- integer(0..255)) do
        {:indexed, i}
      end
    ])
  end

  defp modifiers_gen do
    gen all(mods <- list_of(member_of(@canonical_modifier_order), max_length: 6)) do
      Enum.uniq(mods)
    end
  end

  # Tuple shape returned by the take_cells / take_cells_diff NIFs.
  # The exact set of valid styles is exercised in dedicated properties
  # below; here the goal is just to feed `Cell.from_tuple/1` arbitrary
  # plausible inputs.
  defp cell_tuple_gen do
    gen all(
          col <- integer(0..199),
          row <- integer(0..59),
          symbol <- string(:printable, max_length: 4),
          fg <- paint_color_gen(),
          bg <- paint_color_gen(),
          modifiers <- modifiers_gen(),
          skip <- boolean()
        ) do
      {col, row, symbol, fg, bg, modifiers, skip}
    end
  end

  # Sane terminal dimensions. We cap at 60x30 to keep test runtime
  # predictable — full take_cells encoding allocates per-cell tuples
  # and a property running 100 iterations against a 200x60 grid would
  # add seconds of test time for no extra signal.
  defp dimensions_gen do
    gen all(width <- integer(1..60), height <- integer(1..30)) do
      {width, height}
    end
  end

  # ----------------------------------------------------------------------
  # Conversion round-trips
  # ----------------------------------------------------------------------

  property "Cell.from_tuple round-trips every field at the right position" do
    # Critical regression catch: the NIF tuple is `(col, row, ...)` —
    # column FIRST, row SECOND — while the struct stores `:row` and
    # `:col`. Swapping the two would silently scramble every cell's
    # coordinates. This property fixes both the order and field-name
    # mapping in place across the input space.
    check all(tuple <- cell_tuple_gen()) do
      {col, row, symbol, fg, bg, modifiers, skip} = tuple
      cell = Cell.from_tuple(tuple)

      assert %Cell{
               row: ^row,
               col: ^col,
               symbol: ^symbol,
               fg: ^fg,
               bg: ^bg,
               modifiers: ^modifiers,
               skip: ^skip
             } = cell
    end
  end

  property "Snapshot.from_native preserves width, height, and per-cell tuple data" do
    check all(
            width <- integer(1..40),
            height <- integer(1..20),
            tuples <- list_of(cell_tuple_gen(), min_length: 0, max_length: 10)
          ) do
      payload = %{width: width, height: height, cells: tuples}
      snap = Snapshot.from_native(payload)

      assert %Snapshot{width: ^width, height: ^height} = snap
      assert length(snap.cells) == length(tuples)
      assert Enum.all?(snap.cells, &match?(%Cell{}, &1))

      # Field-by-field equivalence between input tuples and decoded structs.
      for {tuple, cell} <- Enum.zip(tuples, snap.cells) do
        assert Cell.from_tuple(tuple) == cell
      end
    end
  end

  property "Diff.from_native preserves width, height, and per-op tuple data" do
    check all(
            width <- integer(1..40),
            height <- integer(1..20),
            tuples <- list_of(cell_tuple_gen(), min_length: 0, max_length: 10)
          ) do
      payload = %{width: width, height: height, ops: tuples}
      diff = Diff.from_native(payload)

      assert %Diff{width: ^width, height: ^height} = diff
      assert length(diff.ops) == length(tuples)
      assert Enum.all?(diff.ops, &match?(%Cell{}, &1))

      for {tuple, cell} <- Enum.zip(tuples, diff.ops) do
        assert Cell.from_tuple(tuple) == cell
      end
    end
  end

  # ----------------------------------------------------------------------
  # NIF payload shape invariants
  # ----------------------------------------------------------------------

  property "take_cells returns exactly width * height cells for any valid dimensions" do
    check all({width, height} <- dimensions_gen()) do
      ref = Native.cell_session_new(width, height)
      :ok = Native.cell_session_draw(ref, [])

      %{width: w, height: h, cells: cells} = Native.cell_session_take_cells(ref)
      :ok = Native.cell_session_close(ref)

      assert w == width
      assert h == height
      assert length(cells) == width * height
    end
  end

  property "take_cells emits cells in row-major order with correct (col, row) coordinates" do
    check all({width, height} <- dimensions_gen()) do
      ref = Native.cell_session_new(width, height)
      :ok = Native.cell_session_draw(ref, [])

      %{cells: cells} = Native.cell_session_take_cells(ref)
      :ok = Native.cell_session_close(ref)

      expected =
        for y <- 0..(height - 1), x <- 0..(width - 1), do: {x, y}

      coords = Enum.map(cells, fn {x, y, _, _, _, _, _} -> {x, y} end)
      assert coords == expected
    end
  end

  property "first take_cells_diff matches take_cells cell-by-cell (full payload)" do
    # The first diff call after construction has no prior baseline and
    # must emit every cell. That payload should be set-equal to a
    # take_cells snapshot taken at the same moment — both are reading
    # the exact same Buffer.
    check all({width, height} <- dimensions_gen()) do
      ref = Native.cell_session_new(width, height)
      :ok = Native.cell_session_draw(ref, [])

      snapshot = Native.cell_session_take_cells(ref)
      diff = Native.cell_session_take_cells_diff(ref)
      :ok = Native.cell_session_close(ref)

      assert snapshot.width == diff.width
      assert snapshot.height == diff.height
      assert MapSet.new(snapshot.cells) == MapSet.new(diff.ops)
    end
  end

  property "take_cells_diff is empty across two calls with no intervening draw" do
    # Diff is computed from prev_buffer to current; with no draw between
    # calls, the buffer is byte-identical and the diff must be empty.
    check all({width, height} <- dimensions_gen()) do
      ref = Native.cell_session_new(width, height)
      :ok = Native.cell_session_draw(ref, [])
      _full = Native.cell_session_take_cells_diff(ref)

      diff = Native.cell_session_take_cells_diff(ref)
      :ok = Native.cell_session_close(ref)

      assert diff.width == width
      assert diff.height == height
      assert diff.ops == []
    end
  end

  property "diff ops are always a subset of the same-time take_cells snapshot" do
    # For any sequence of draws, the cells emitted by take_cells_diff
    # at time T must be a subset (as a set) of the cells in
    # take_cells at time T. The diff filters; it never invents.
    check all(
            {width, height} <- dimensions_gen(),
            text <- string(:ascii, min_length: 0, max_length: 8)
          ) do
      ref = Native.cell_session_new(width, height)
      :ok = Native.cell_session_draw(ref, [])
      _baseline = Native.cell_session_take_cells_diff(ref)

      paragraph = %Paragraph{text: text}
      rect = %Rect{x: 0, y: 0, width: width, height: height}
      commands = Bridge.encode_commands!([{paragraph, rect}])
      :ok = Native.cell_session_draw(ref, commands)

      snapshot = Native.cell_session_take_cells(ref)
      diff = Native.cell_session_take_cells_diff(ref)
      :ok = Native.cell_session_close(ref)

      ops_set = MapSet.new(diff.ops)
      cells_set = MapSet.new(snapshot.cells)
      assert MapSet.subset?(ops_set, cells_set)
    end
  end

  # ----------------------------------------------------------------------
  # Encoder fidelity at scale
  # ----------------------------------------------------------------------

  property "any paint color round-trips through take_cells unchanged" do
    check all(color <- paint_color_gen()) do
      paragraph = %Paragraph{text: "X", style: %Style{fg: color}}
      rect = %Rect{x: 0, y: 0, width: 1, height: 1}
      commands = Bridge.encode_commands!([{paragraph, rect}])

      ref = Native.cell_session_new(1, 1)
      :ok = Native.cell_session_draw(ref, commands)
      %{cells: [cell]} = Native.cell_session_take_cells(ref)
      :ok = Native.cell_session_close(ref)

      assert {0, 0, "X", ^color, :reset, [], false} = cell
    end
  end

  property "any modifier subset round-trips in canonical sorted order regardless of input order" do
    # `list_of(member_of(...))` naturally generates lists in arbitrary
    # orders — including reverse-canonical, partially-sorted, and with
    # duplicates. The encoder MUST emit modifiers in canonical bitflag
    # order regardless, so consumers can compare encoded modifier
    # lists with `==`. Duplicates collapse (a modifier is either set
    # or not in the bitflag).
    check all(input_modifiers <- list_of(member_of(@canonical_modifier_order), max_length: 12)) do
      paragraph = %Paragraph{text: "X", style: %Style{modifiers: input_modifiers}}
      rect = %Rect{x: 0, y: 0, width: 1, height: 1}
      commands = Bridge.encode_commands!([{paragraph, rect}])

      ref = Native.cell_session_new(1, 1)
      :ok = Native.cell_session_draw(ref, commands)
      %{cells: [{0, 0, "X", _fg, _bg, mods, false}]} = Native.cell_session_take_cells(ref)
      :ok = Native.cell_session_close(ref)

      expected = Enum.filter(@canonical_modifier_order, &(&1 in input_modifiers))
      assert mods == expected
    end
  end

  # ----------------------------------------------------------------------
  # Wrapper API parity
  # ----------------------------------------------------------------------

  property "CellSession.take_cells/1 produces structs equivalent to Snapshot.from_native of the raw NIF" do
    # The wrapper is documented to be a thin transformation layer over
    # the NIF. This property pins that contract: for any session at any
    # dimensions, the wrapper output equals applying Snapshot.from_native
    # to the raw NIF output.
    check all({width, height} <- dimensions_gen()) do
      session = CellSession.new(width, height)
      :ok = CellSession.draw(session, [])

      via_wrapper = CellSession.take_cells(session)
      via_nif = Native.cell_session_take_cells(session.ref)
      :ok = CellSession.close(session)

      assert via_wrapper == Snapshot.from_native(via_nif)
    end
  end

  property "CellSession.take_cells_diff/1 is empty after a no-op draw" do
    check all({width, height} <- dimensions_gen()) do
      session = CellSession.new(width, height)
      :ok = CellSession.draw(session, [])
      _baseline = CellSession.take_cells_diff(session)

      diff = CellSession.take_cells_diff(session)
      :ok = CellSession.close(session)

      assert %Diff{width: ^width, height: ^height, ops: []} = diff
    end
  end
end
