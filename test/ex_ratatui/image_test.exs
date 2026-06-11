defmodule ExRatatui.ImageTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Image
  alias ExRatatui.Widgets.Image, as: ImageWidget

  doctest ExRatatui.Image

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

    test "accepts every Style.color() shape for :background" do
      # nil + raw RGB
      assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: nil)
      assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: {0, 0, 0})
      assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: {255, 128, 64})

      # Tagged RGB
      assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: {:rgb, 0, 0, 0})
      assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: {:rgb, 200, 100, 50})

      # Named ANSI colors
      for name <- [
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
        assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: name)
      end

      # :reset maps to nil (transparent)
      assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: :reset)

      # xterm 256-color indices — exercise EVERY clause of indexed_to_rgb.
      # Indices 0..15 each route through their own case branch
      # (mapping to a named ANSI color); 16..231 hit the 6×6×6 cube
      # arithmetic; 232..255 hit the grayscale ramp.
      for n <- 0..15 do
        assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: {:indexed, n})
      end

      # Cube band — pick a few that exercise both `cube_step(0)` and
      # `cube_step(i)` arms.
      assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: {:indexed, 16})
      assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: {:indexed, 100})
      assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: {:indexed, 231})

      # Grayscale band.
      assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: {:indexed, 232})
      assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: {:indexed, 240})
      assert {:ok, %ImageWidget{}} = Image.new(@valid_png, background: {:indexed, 255})
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

    test "raises on out-of-range {:rgb, ...} background" do
      assert_raise ArgumentError, ~r/:background/, fn ->
        Image.new(@valid_png, background: {:rgb, -1, 0, 0})
      end
    end

    test "raises on out-of-range {:indexed, ...} background" do
      assert_raise ArgumentError, ~r/:background/, fn ->
        Image.new(@valid_png, background: {:indexed, 999})
      end
    end

    test "raises on unknown atom background" do
      assert_raise ArgumentError, ~r/:background/, fn ->
        Image.new(@valid_png, background: :neon_pink)
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

  describe "probe_terminal/0" do
    # The live NIF probe (Picker::from_query_stdio) writes to stdout
    # and waits up to 2s for the terminal's reply on stdin. Tests
    # default to a fast `:error` fake via test_helper.exs so we don't
    # queue dirty-IO scheduler threads. Branch behavior is covered
    # exhaustively through the `probe_with/1` test seam below.
    test "honors the Application config override" do
      assert {:error, :no_probe_in_tests} = Image.probe_terminal()
    end

    test "wraps a successful probe tuple as {:ok, %{protocol:, font_size:}}" do
      fake_probe = fn -> {:kitty, {10, 20}} end
      assert {:ok, %{protocol: :kitty, font_size: {10, 20}}} = Image.probe_with(fake_probe)
    end

    test "forwards probe errors as-is" do
      fake_probe = fn -> {:error, :unsupported} end
      assert {:error, :unsupported} = Image.probe_with(fake_probe)
    end
  end

  describe "auto_local_protocol/1" do
    test "honors the Application config override and soft-fails" do
      terminal = ExRatatui.init_test_terminal(10, 3)
      on_exit(fn -> ExRatatui.Native.restore_terminal(terminal) end)

      assert {:error, :no_probe_in_tests} = Image.auto_local_protocol(terminal)
    end

    test "caches a successful probe on the terminal" do
      terminal = ExRatatui.init_test_terminal(10, 3)
      on_exit(fn -> ExRatatui.Native.restore_terminal(terminal) end)

      fake_probe = fn -> {:sixel, {7, 14}} end
      assert :ok = Image.auto_local_protocol_with(terminal, fake_probe)
    end

    test "propagates probe errors" do
      terminal = ExRatatui.init_test_terminal(10, 3)
      on_exit(fn -> ExRatatui.Native.restore_terminal(terminal) end)

      fake_probe = fn -> {:error, :nope} end
      assert {:error, :nope} = Image.auto_local_protocol_with(terminal, fake_probe)
    end
  end

  describe "terminal_set_local_probe/3 end-to-end" do
    # The strongest signal that the probe is wired through draw_frame:
    # same source image, same widget, two different cached probes — the
    # rendered buffer contents must differ. If the local_probe field
    # weren't being read in rendering.rs, both runs would resolve `:auto`
    # to halfblocks and produce identical cells.
    test "kitty probe renders different cells from halfblocks probe" do
      {:ok, widget} = Image.new(@valid_png, protocol: :auto)
      rect = %ExRatatui.Layout.Rect{x: 0, y: 0, width: 6, height: 4}

      halfblocks_buf = draw_with_probe(widget, rect, :halfblocks, {8, 16})
      kitty_buf = draw_with_probe(widget, rect, :kitty, {10, 20})

      refute halfblocks_buf == kitty_buf,
             "expected different buffer contents under :halfblocks vs :kitty local_probe"
    end

    test "setting :auto clears the cached probe" do
      terminal = ExRatatui.init_test_terminal(6, 4)
      on_exit(fn -> ExRatatui.Native.restore_terminal(terminal) end)

      assert :ok = ExRatatui.Native.terminal_set_local_probe(terminal, :kitty, {10, 20})
      assert :ok = ExRatatui.Native.terminal_set_local_probe(terminal, :auto, {0, 0})
    end
  end

  defp draw_with_probe(widget, rect, protocol, font_size) do
    terminal = ExRatatui.init_test_terminal(rect.width, rect.height)
    :ok = ExRatatui.Native.terminal_set_local_probe(terminal, protocol, font_size)
    :ok = ExRatatui.draw(terminal, [{widget, rect}])
    content = ExRatatui.get_buffer_content(terminal)
    :ok = ExRatatui.Native.restore_terminal(terminal)
    content
  end

  # Captured module function — :telemetry warns at info level when
  # attached handlers are local/anonymous functions, citing a perf
  # penalty per dispatch. Using `&__MODULE__.forward_tel/4` silences it.
  def forward_tel(event, measurements, metadata, %{probe: probe}) do
    send(probe, {:tel, event, measurements, metadata})
  end

  describe "render_size/4" do
    # The full Fit/Crop/Scale matrix matters here — these are the
    # functions that drive demo status displays and any layout code
    # that needs to know where an image will actually paint.

    test ":scale upscales aspect-preservingly to fill the target" do
      # 400x300 source, 80x24 cells, 10x20 font → 800x480 target px
      # Image aspect 1.333, target aspect 1.667 → height-limited
      # height = 480, width = 480 * (400/300) = 640
      assert {640, 480} = Image.render_size({400, 300}, {80, 24}, {10, 20}, :scale)
    end

    test ":fit clamps to source dimensions when source < target on both axes" do
      # Same inputs as above, but :fit refuses to upscale.
      assert {400, 300} = Image.render_size({400, 300}, {80, 24}, {10, 20}, :fit)
    end

    test ":crop also clamps to source dimensions in that case" do
      # The bug-of-the-day from the user: :fit and :crop produce the
      # same output when source is smaller than target on both axes.
      assert {400, 300} = Image.render_size({400, 300}, {80, 24}, {10, 20}, :crop)
    end

    test ":fit downscales aspect-preservingly when source exceeds target" do
      # 2000x1000 source, 80x24 cells, 10x20 font → 800x480 target
      # Image aspect 2.0, target aspect 1.667 → width-limited
      # width = 800, height = 800 / 2 = 400
      assert {800, 400} = Image.render_size({2000, 1000}, {80, 24}, {10, 20}, :fit)
    end

    test ":crop snaps to target dimensions when source exceeds target" do
      # Same overflowing source — :crop returns target dims (will crop)
      assert {800, 480} = Image.render_size({2000, 1000}, {80, 24}, {10, 20}, :crop)
    end

    test ":scale also handles oversized sources by downscaling" do
      assert {800, 400} = Image.render_size({2000, 1000}, {80, 24}, {10, 20}, :scale)
    end

    test "respects custom font sizes" do
      # 8x16 font (default ratatui-image fallback) instead of 10x20
      # 400x300 source, 80x24 cells, 8x16 font → 640x384 target px
      # Image aspect 1.333, target aspect 1.667 → height-limited
      # height = 384, width = 384 * (400/300) = 512
      assert {512, 384} = Image.render_size({400, 300}, {80, 24}, {8, 16}, :scale)
    end

    test "1×1 cell area is well-defined for every mode" do
      # 1000×1000 source, 1×1 cell, {10, 20} font → target {10, 20} px.
      # Image aspect 1.0 into rect aspect 0.5 → width-limited everywhere.
      # :fit  → fit_area(1000, 1000, min(10, 1000), min(20, 1000)) → (10, 10)
      # :crop → (min(1000, 10), min(1000, 20)) → (10, 20)
      # :scale → fit_area(1000, 1000, 10, 20) → (10, 10)
      assert {10, 10} = Image.render_size({1000, 1000}, {1, 1}, {10, 20}, :fit)
      assert {10, 20} = Image.render_size({1000, 1000}, {1, 1}, {10, 20}, :crop)
      assert {10, 10} = Image.render_size({1000, 1000}, {1, 1}, {10, 20}, :scale)
    end
  end

  describe "telemetry [:ex_ratatui, :image, :decode]" do
    setup do
      ref = make_ref()

      :telemetry.attach_many(
        ref,
        [
          [:ex_ratatui, :image, :decode, :start],
          [:ex_ratatui, :image, :decode, :stop]
        ],
        &__MODULE__.forward_tel/4,
        %{probe: self()}
      )

      on_exit(fn -> :telemetry.detach(ref) end)
      :ok
    end

    test "successful new/2 emits start + stop with format and dimensions" do
      assert {:ok, _} = Image.new(@valid_png)

      assert_receive {:tel, [:ex_ratatui, :image, :decode, :start], start_meas,
                      %{format: :png, bytes: bytes}}

      assert is_integer(start_meas.monotonic_time)
      assert bytes == byte_size(@valid_png)

      assert_receive {:tel, [:ex_ratatui, :image, :decode, :stop], stop_meas,
                      %{format: :png, bytes: ^bytes, width: 1, height: 1}}

      assert is_integer(stop_meas.duration)
    end

    test "failed new/2 emits start + stop with :error metadata and no width/height" do
      assert {:error, {:decode_failed, _}} = Image.new("not an image")

      assert_receive {:tel, [:ex_ratatui, :image, :decode, :start], _, %{format: :unknown}}

      assert_receive {:tel, [:ex_ratatui, :image, :decode, :stop], _, stop_meta}
      assert {:decode_failed, _} = stop_meta.error
      refute Map.has_key?(stop_meta, :width)
      refute Map.has_key?(stop_meta, :height)
    end

    test "detects every supported format from magic bytes" do
      # Build tiny payloads with the right magic bytes for each format.
      # Decoding may still fail (we only seed the magic), but the
      # format-detection branch is what we're covering here — telemetry
      # `:format` reflects whatever the byte prefix matched.
      cases = [
        {:jpeg, <<0xFF, 0xD8, 0xFF, 0x00>>},
        {:gif, "GIF87a\0"},
        {:gif, "GIF89a\0"},
        {:webp, "RIFF" <> :binary.copy(<<0>>, 4) <> "WEBP" <> :binary.copy(<<0>>, 4)},
        {:bmp, "BM" <> :binary.copy(<<0>>, 10)}
      ]

      for {expected_format, bytes} <- cases do
        _ = Image.new(bytes)

        assert_receive {:tel, [:ex_ratatui, :image, :decode, :start], _,
                        %{format: ^expected_format}}

        assert_receive {:tel, [:ex_ratatui, :image, :decode, :stop], _, _}
      end
    end
  end
end
