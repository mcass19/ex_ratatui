defmodule ExRatatui.Widgets.Viewport3DTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Widgets.Viewport3D

  doctest ExRatatui.Widgets.Viewport3D

  test "defaults to a braille rasterized empty scene" do
    widget = %Viewport3D{}
    assert widget.render_mode == :braille
    assert widget.pipeline == :rasterize
    assert widget.scene.objects == []
    assert widget.block == nil
  end
end
