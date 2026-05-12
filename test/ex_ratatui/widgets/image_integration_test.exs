defmodule ExRatatui.Widgets.ImageIntegrationTest do
  @moduledoc """
  End-to-end checks that the chunk-5 caps-forwarding through the
  recursive widget render path actually works.

  Popup and WidgetList both call `render_widget_data` internally with
  the `TransportCaps` they were given. An Image nested inside either
  must therefore fall back to halfblocks when drawn via CellSession,
  even when the user requested Kitty. If the caps weren't forwarded,
  the nested image would resolve `:auto` differently from the same
  image drawn directly.
  """

  use ExUnit.Case, async: true

  alias ExRatatui.Bridge
  alias ExRatatui.Image
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Native
  alias ExRatatui.Widgets.{Popup, WidgetList}

  @valid_png Base.decode64!(
               "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
             )

  defp draw_cells(widget, %Rect{} = rect) do
    commands = Bridge.encode_commands!([{widget, rect}])
    ref = Native.cell_session_new(rect.width, rect.height)
    :ok = Native.cell_session_draw(ref, commands)
    %{cells: cells} = Native.cell_session_take_cells(ref)
    :ok = Native.cell_session_close(ref)
    cells
  end

  describe "Image inside a Popup" do
    test "falls back to halfblocks even when the inner image requested kitty" do
      {:ok, kitty_image} = Image.new(@valid_png, protocol: :kitty)
      {:ok, half_image} = Image.new(@valid_png, protocol: :halfblocks)

      rect = %Rect{x: 0, y: 0, width: 12, height: 8}

      kitty_popup = %Popup{
        content: kitty_image,
        percent_width: 100,
        percent_height: 100
      }

      half_popup = %Popup{
        content: half_image,
        percent_width: 100,
        percent_height: 100
      }

      # CellSession's caps must propagate through Popup's recursive
      # render_widget_data call. Both popups should produce identical
      # cells because both inner images resolve to halfblocks.
      assert draw_cells(kitty_popup, rect) == draw_cells(half_popup, rect)
    end
  end

  describe "Image inside a WidgetList" do
    test "nested image falls back to halfblocks under CellSession" do
      {:ok, kitty_image} = Image.new(@valid_png, protocol: :kitty)
      {:ok, half_image} = Image.new(@valid_png, protocol: :halfblocks)

      rect = %Rect{x: 0, y: 0, width: 10, height: 6}

      kitty_list = %WidgetList{items: [{kitty_image, 6}]}
      half_list = %WidgetList{items: [{half_image, 6}]}

      assert draw_cells(kitty_list, rect) == draw_cells(half_list, rect)
    end
  end
end
