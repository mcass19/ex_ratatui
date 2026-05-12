defmodule ExRatatui.Property.ImagePropertyTest do
  @moduledoc """
  Property-based invariants for the image render pipeline.

  These properties exercise the full chain — `ExRatatui.Image.new/2`
  decode → `Bridge.encode_commands!` → `Native.cell_session_draw` →
  `take_cells` — over the cross product of supported `:protocol` and
  `:resize` options on randomly-sized rects. Per-clause unit tests
  cover individual branches; these properties confirm the whole chain
  is total: no rect/protocol/resize combination crashes, and the
  emitted cell payload always matches the requested rect dimensions.

  We use a single fixture PNG (smallest valid 1x1) for all properties.
  Varying image bytes adds noise without exercising the parts of the
  pipeline that actually depend on input shape — `image::load_from_memory`
  already has property coverage upstream in the `image` crate.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExRatatui.Bridge
  alias ExRatatui.Image
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native

  @valid_png Base.decode64!(
               "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
             )

  @protocols [:auto, :halfblocks, :kitty, :sixel, :iterm2]
  @resizes [:fit, :crop, :scale]

  # Generators -------------------------------------------------------------

  defp rect_gen do
    gen all(
          width <- integer(1..40),
          height <- integer(1..20)
        ) do
      %Rect{x: 0, y: 0, width: width, height: height}
    end
  end

  defp protocol_gen, do: member_of(@protocols)
  defp resize_gen, do: member_of(@resizes)

  # Properties -------------------------------------------------------------

  property "draw produces exactly width*height cells for any rect, protocol, and resize" do
    check all(
            rect <- rect_gen(),
            protocol <- protocol_gen(),
            resize <- resize_gen()
          ) do
      {:ok, widget} = Image.new(@valid_png, protocol: protocol, resize: resize)
      commands = Bridge.encode_commands!([{widget, rect}])

      ref = Native.cell_session_new(rect.width, rect.height)
      assert :ok = Native.cell_session_draw(ref, commands)
      %{cells: cells} = Native.cell_session_take_cells(ref)
      :ok = Native.cell_session_close(ref)

      assert length(cells) == rect.width * rect.height
    end
  end

  property "every cell from take_cells lies inside the requested rect" do
    check all(
            rect <- rect_gen(),
            protocol <- protocol_gen()
          ) do
      {:ok, widget} = Image.new(@valid_png, protocol: protocol)
      commands = Bridge.encode_commands!([{widget, rect}])

      ref = Native.cell_session_new(rect.width, rect.height)
      :ok = Native.cell_session_draw(ref, commands)
      %{cells: cells} = Native.cell_session_take_cells(ref)
      :ok = Native.cell_session_close(ref)

      for {x, y, _sym, _fg, _bg, _mods, _skip} <- cells do
        assert x >= 0 and x < rect.width, "x=#{x} out of #{rect.width}"
        assert y >= 0 and y < rect.height, "y=#{y} out of #{rect.height}"
      end
    end
  end

  property "two identical draws produce identical cells (deterministic render)" do
    check all(
            rect <- rect_gen(),
            protocol <- protocol_gen(),
            resize <- resize_gen()
          ) do
      {:ok, widget} = Image.new(@valid_png, protocol: protocol, resize: resize)
      commands = Bridge.encode_commands!([{widget, rect}])

      a_ref = Native.cell_session_new(rect.width, rect.height)
      :ok = Native.cell_session_draw(a_ref, commands)
      %{cells: a_cells} = Native.cell_session_take_cells(a_ref)
      :ok = Native.cell_session_close(a_ref)

      b_ref = Native.cell_session_new(rect.width, rect.height)
      :ok = Native.cell_session_draw(b_ref, commands)
      %{cells: b_cells} = Native.cell_session_take_cells(b_ref)
      :ok = Native.cell_session_close(b_ref)

      assert a_cells == b_cells
    end
  end

  property "every CellSession draw forces halfblocks regardless of protocol" do
    # CellSession-style transports stamp TransportCaps::CellOnly, which
    # makes resolve_protocol force halfblocks. The strongest cross-protocol
    # assertion: cells for any non-halfblocks protocol must match cells
    # for :halfblocks on the same rect.
    {:ok, halfblocks_widget} = Image.new(@valid_png, protocol: :halfblocks)

    check all(
            rect <- rect_gen(),
            other <- member_of([:auto, :kitty, :sixel, :iterm2])
          ) do
      {:ok, other_widget} = Image.new(@valid_png, protocol: other)

      half_cells =
        draw_via_cell_session(halfblocks_widget, rect)

      other_cells =
        draw_via_cell_session(other_widget, rect)

      assert half_cells == other_cells,
             "CellSession should force halfblocks for #{inspect(other)}"
    end
  end

  defp draw_via_cell_session(widget, rect) do
    commands = Bridge.encode_commands!([{widget, rect}])
    ref = Native.cell_session_new(rect.width, rect.height)
    :ok = Native.cell_session_draw(ref, commands)
    %{cells: cells} = Native.cell_session_take_cells(ref)
    :ok = Native.cell_session_close(ref)
    cells
  end
end
