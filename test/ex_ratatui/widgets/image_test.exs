defmodule ExRatatui.Widgets.ImageTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Bridge
  alias ExRatatui.Image
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native
  alias ExRatatui.Widgets.Image, as: ImageWidget

  defp draw_through_cell_session(widget, width, height) do
    rect = %Rect{x: 0, y: 0, width: width, height: height}
    commands = Bridge.encode_commands!([{widget, rect}])
    ref = Native.cell_session_new(width, height)
    :ok = Native.cell_session_draw(ref, commands)
    %{cells: cells} = Native.cell_session_take_cells(ref)
    :ok = Native.cell_session_close(ref)
    cells
  end

  @valid_png Base.decode64!(
               "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
             )

  describe "%ExRatatui.Widgets.Image{}" do
    test "defaults state to nil" do
      assert %ImageWidget{state: nil} = %ImageWidget{}
    end
  end

  describe "Bridge encoding" do
    test "encodes a valid widget into the expected NIF map" do
      {:ok, widget} = Image.new(@valid_png)
      rect = %Rect{x: 1, y: 2, width: 10, height: 5}

      assert {%{"type" => "image", "state" => state}, %{"x" => 1, "y" => 2}} =
               Bridge.encode_command({widget, rect})

      assert is_reference(state)
    end

    test "raises when state is nil" do
      assert_raise ArgumentError, ~r/image\.state is required/, fn ->
        Bridge.encode_command({%ImageWidget{}, %Rect{x: 0, y: 0, width: 1, height: 1}})
      end
    end

    test "raises when state is not a reference" do
      assert_raise ArgumentError, ~r/must be a reference/, fn ->
        Bridge.encode_command(
          {%ImageWidget{state: :not_a_ref}, %Rect{x: 0, y: 0, width: 1, height: 1}}
        )
      end
    end
  end

  describe "distributed snapshot path" do
    # The Server's snapshot_stateful_widgets replaces the
    # ResourceArc-bearing %Image{state: ref} with a snapshot tuple
    # before the widget tree is sent over distribution. The receiving
    # node's decode_image must accept that tuple and reconstruct a
    # fresh ImageResource. This test runs the round-trip locally to
    # exercise the snapshot encode + decode path without needing two
    # BEAM nodes.
    test "kitty snapshot decodes locally and renders identical cells to a live image" do
      {:ok, %ImageWidget{state: ref}} = Image.new(@valid_png, protocol: :kitty)
      snapshot = Native.image_snapshot(ref)

      live_cells = draw_through_cell_session(%ImageWidget{state: ref}, 4, 4)
      snap_cells = draw_through_cell_session(%ImageWidget{state: snapshot}, 4, 4)

      # Both paths land in CellSession which forces halfblocks; the
      # snapshot must therefore produce byte-identical cells.
      assert live_cells == snap_cells
    end

    test "snapshot preserves resize and background" do
      {:ok, %ImageWidget{state: ref}} =
        Image.new(@valid_png, protocol: :sixel, resize: :crop, background: {12, 34, 56})

      assert {bytes, :sixel, :crop, {12, 34, 56}} = Native.image_snapshot(ref)
      assert is_binary(bytes)
      assert byte_size(bytes) == byte_size(@valid_png)
    end

    test "Bridge accepts a snapshot tuple as state" do
      {:ok, %ImageWidget{state: ref}} = Image.new(@valid_png)
      snap = Native.image_snapshot(ref)

      assert {%{"type" => "image", "state" => ^snap}, _rect} =
               Bridge.encode_command(
                 {%ImageWidget{state: snap}, %Rect{x: 0, y: 0, width: 4, height: 4}}
               )
    end

    test "decode_image rejects bytes that aren't decodable" do
      bad_snapshot = {<<"not an image">>, :halfblocks, :fit, nil}
      rect = %Rect{x: 0, y: 0, width: 4, height: 4}
      commands = Bridge.encode_commands!([{%ImageWidget{state: bad_snapshot}, rect}])

      ref = Native.cell_session_new(4, 4)

      assert {:error, message} = Native.cell_session_draw(ref, commands)
      assert message =~ "snapshot bytes failed to decode" or message =~ "image.state"

      Native.cell_session_close(ref)
    end
  end

  describe "CellSession protocol fallback" do
    # CellSession-style transports can only carry cells, never escape
    # sequences, so the render pipeline must force Halfblocks regardless
    # of what the user asked for. The cells produced for :kitty must
    # therefore be byte-identical to the cells produced for :halfblocks
    # when the same source image is rendered into the same rect.
    test "kitty request renders identical cells to halfblocks via CellSession" do
      {:ok, kitty} = Image.new(@valid_png, protocol: :kitty)
      {:ok, half} = Image.new(@valid_png, protocol: :halfblocks)

      kitty_cells = draw_through_cell_session(kitty, 4, 4)
      half_cells = draw_through_cell_session(half, 4, 4)

      assert kitty_cells == half_cells
    end

    test "sixel and iterm2 requests also fall back to halfblocks" do
      {:ok, sixel} = Image.new(@valid_png, protocol: :sixel)
      {:ok, iterm2} = Image.new(@valid_png, protocol: :iterm2)
      {:ok, half} = Image.new(@valid_png, protocol: :halfblocks)

      assert draw_through_cell_session(sixel, 4, 4) ==
               draw_through_cell_session(half, 4, 4)

      assert draw_through_cell_session(iterm2, 4, 4) ==
               draw_through_cell_session(half, 4, 4)
    end
  end
end
