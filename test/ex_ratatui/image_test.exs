defmodule ExRatatui.ImageTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Image
  alias ExRatatui.Widgets.Image, as: ImageWidget

  # Smallest valid PNG: 1x1 white pixel, 67 bytes. Decoded by every
  # ratatui-image-supported backend.
  @valid_png Base.decode64!(
               "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
             )

  describe "new/2" do
    test "returns {:ok, widget} on valid bytes with default opts" do
      assert {:ok, %ImageWidget{state: ref}} = Image.new(@valid_png)
      assert is_reference(ref)
    end

    test "returns {:error, {:decode_failed, msg}} on garbage bytes" do
      assert {:error, {:decode_failed, msg}} = Image.new("not an image, not at all")
      assert is_binary(msg)
      assert msg != ""
    end

    test "accepts every supported protocol atom" do
      for protocol <- [:auto, :halfblocks, :kitty, :sixel, :iterm2] do
        assert {:ok, %ImageWidget{}} = Image.new(@valid_png, protocol: protocol)
      end
    end

    test "accepts every supported resize atom" do
      for resize <- [:fit, :crop, :scale] do
        assert {:ok, %ImageWidget{}} = Image.new(@valid_png, resize: resize)
      end
    end

    test "accepts nil and {r, g, b} backgrounds" do
      assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: nil)
      assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: {0, 0, 0})
      assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: {255, 128, 64})
    end

    test "raises on unknown protocol" do
      assert_raise ArgumentError, ~r/:protocol/, fn ->
        Image.new(@valid_png, protocol: :gibberish)
      end
    end

    test "raises on unknown resize" do
      assert_raise ArgumentError, ~r/:resize/, fn ->
        Image.new(@valid_png, resize: :gibberish)
      end
    end

    test "raises on out-of-range background channel" do
      assert_raise ArgumentError, ~r/:background/, fn ->
        Image.new(@valid_png, background: {300, 0, 0})
      end
    end

    test "raises on non-tuple background" do
      assert_raise ArgumentError, ~r/:background/, fn ->
        Image.new(@valid_png, background: :red)
      end
    end
  end

  describe "dimensions/1" do
    test "returns {width, height} from a widget struct" do
      {:ok, widget} = Image.new(@valid_png)
      assert {1, 1} = Image.dimensions(widget)
    end

    test "returns {width, height} from a bare reference" do
      {:ok, %ImageWidget{state: ref}} = Image.new(@valid_png)
      assert {1, 1} = Image.dimensions(ref)
    end
  end
end
