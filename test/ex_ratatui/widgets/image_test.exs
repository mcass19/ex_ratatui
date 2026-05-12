defmodule ExRatatui.Widgets.ImageTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Bridge
  alias ExRatatui.Image
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Image, as: ImageWidget

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
end
