defmodule ExRatatui.Image do
  @moduledoc """
  Construct image widgets from raw image bytes.

  Decodes PNG/JPEG/GIF/WebP/BMP binaries into a stateful widget handle
  backed by [ratatui-image](https://github.com/ratatui/ratatui-image). The
  same widget renders across every ExRatatui transport: in a Kitty-graphics
  capable local terminal it uses the Kitty protocol; over `CellSession`
  (Livebook / Kino) it falls back to Unicode halfblocks automatically.

  ```elixir
  {:ok, picture} = ExRatatui.Image.new(File.read!("priv/slides/cover.png"))

  # Or pick explicit options
  {:ok, picture} =
    ExRatatui.Image.new(bytes, resize: :crop, protocol: :kitty)
  ```

  ## Options

    * `:protocol` - which terminal image protocol to render with. One of
      `:auto` (default), `:halfblocks`, `:kitty`, `:sixel`, `:iterm2`.
      `:auto` resolves at render time using the transport's capabilities
      (see the [Images guide](images.md) for the resolution table).
      Explicit protocols are honored except over `CellSession`-style
      transports where `:halfblocks` is forced.
    * `:resize` - resize strategy. `:fit` (default, preserve aspect ratio
      inside the rect), `:crop` (preserve aspect, fill the rect, crop the
      overflow), or `:scale` (stretch to fill).
    * `:background` - background color used to fill transparency / unused
      area. Either `nil` (default, transparent) or an `{r, g, b}` tuple
      with each channel in `0..255`.

  ## Errors

  `new/2` returns `{:ok, widget}` on success, or
  `{:error, {:decode_failed, message}}` when the bytes can't be decoded
  as a supported image format.

  ## Telemetry

  Each `new/2` call emits a `[:ex_ratatui, :image, :decode]` span:

    * `:start` metadata — `%{format: atom, bytes: non_neg_integer}`.
      `:format` is one of `:png`, `:jpeg`, `:gif`, `:webp`, `:bmp`, or
      `:unknown` (sniffed from the magic bytes).
    * `:stop` metadata — adds `:width` and `:height` on success, or
      `:error` (reason) on failure.

  Per-render encode timing (Kitty / Sixel / iTerm2 payload generation)
  isn't emitted as its own event — it happens inside the Rust render
  NIF; the existing `[:ex_ratatui, :render, :frame]` span covers total
  frame time, which includes image encode.
  """

  alias ExRatatui.Native
  alias ExRatatui.Widgets.Image, as: Widget

  @type protocol :: :auto | :halfblocks | :kitty | :sixel | :iterm2
  @type resize :: :fit | :crop | :scale
  @type background :: nil | {0..255, 0..255, 0..255}

  @type new_opts :: [
          protocol: protocol(),
          resize: resize(),
          background: background()
        ]

  @valid_protocols [:auto, :halfblocks, :kitty, :sixel, :iterm2]
  @valid_resizes [:fit, :crop, :scale]

  @doc """
  Decode image `bytes` into a stateful widget.

  Returns `{:ok, %ExRatatui.Widgets.Image{}}` on success, or
  `{:error, {:decode_failed, message}}` if `bytes` is not a valid
  PNG/JPEG/GIF/WebP/BMP payload. The format is auto-detected from the
  bytes — no extension or content-type hint is required.
  """
  @spec new(binary(), new_opts()) ::
          {:ok, Widget.t()} | {:error, {:decode_failed, String.t()}}
  def new(bytes, opts \\ []) when is_binary(bytes) and is_list(opts) do
    nif_opts = %{
      protocol: validate_protocol(Keyword.get(opts, :protocol, :auto)),
      resize: validate_resize(Keyword.get(opts, :resize, :fit)),
      background: validate_background(Keyword.get(opts, :background))
    }

    format = detect_format(bytes)
    start_meta = %{format: format, bytes: byte_size(bytes)}

    # `:telemetry.span/3` lets us enrich the `:stop` metadata with the
    # decoded image dimensions on success, while keeping `:start` lean.
    # Failure cases fall through with just `format` and `bytes` (no
    # width/height to report) plus an `:error` metadata key.
    :telemetry.span([:ex_ratatui, :image, :decode], start_meta, fn ->
      case Native.image_new(bytes, nif_opts) do
        ref when is_reference(ref) ->
          {w, h} = Native.image_dimensions(ref)
          stop_meta = Map.merge(start_meta, %{width: w, height: h})
          {{:ok, %Widget{state: ref}}, stop_meta}

        {:error, reason} = err ->
          stop_meta = Map.put(start_meta, :error, reason)
          {err, stop_meta}
      end
    end)
  end

  # Detect the image format from magic bytes. Returns one of `:png`,
  # `:jpeg`, `:gif`, `:webp`, `:bmp`, or `:unknown`. We do this in Elixir
  # rather than asking the NIF so telemetry has the format atom even
  # when decode fails further down. The five names match what the
  # `image` crate's auto-format detector accepts.
  defp detect_format(<<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>), do: :png
  defp detect_format(<<0xFF, 0xD8, 0xFF, _::binary>>), do: :jpeg
  defp detect_format(<<"GIF87a", _::binary>>), do: :gif
  defp detect_format(<<"GIF89a", _::binary>>), do: :gif
  defp detect_format(<<"RIFF", _::4-binary, "WEBP", _::binary>>), do: :webp
  defp detect_format(<<"BM", _::binary>>), do: :bmp
  defp detect_format(_), do: :unknown

  @doc """
  Return the `{width, height}` of the decoded source image in pixels.

  This is the original image's pixel size, not its rendered cell size.
  Useful for laying out around an image of known aspect ratio.
  """
  @spec dimensions(Widget.t() | reference()) ::
          {non_neg_integer(), non_neg_integer()}
  def dimensions(%Widget{state: ref}) when is_reference(ref),
    do: Native.image_dimensions(ref)

  def dimensions(ref) when is_reference(ref),
    do: Native.image_dimensions(ref)

  defp validate_protocol(p) when p in @valid_protocols, do: p

  defp validate_protocol(other) do
    raise ArgumentError,
          "expected :protocol to be one of #{inspect(@valid_protocols)}, got: #{inspect(other)}"
  end

  defp validate_resize(r) when r in @valid_resizes, do: r

  defp validate_resize(other) do
    raise ArgumentError,
          "expected :resize to be one of #{inspect(@valid_resizes)}, got: #{inspect(other)}"
  end

  defp validate_background(nil), do: nil

  defp validate_background({r, g, b})
       when is_integer(r) and r in 0..255 and is_integer(g) and g in 0..255 and is_integer(b) and
              b in 0..255,
       do: {r, g, b}

  defp validate_background(other) do
    raise ArgumentError,
          "expected :background to be nil or a {r, g, b} tuple in 0..255, got: #{inspect(other)}"
  end

  @type probe_result :: %{protocol: protocol(), font_size: {pos_integer(), pos_integer()}}

  @doc """
  Queries the local terminal for image-protocol capabilities and font size.

  Sends a small escape-sequence probe to stdout and waits for the
  terminal's reply on stdin (ratatui-image's `Picker::from_query_stdio`).
  Runs on a dirty IO scheduler so it doesn't block the BEAM main run
  queue. Returns the detected protocol and cell pixel size on success, or
  `{:error, reason}` if the terminal didn't respond, isn't a TTY, or the
  probe timed out.

  Use this when you want to decide your own fallback policy. Most apps
  should call `auto_local_protocol/1` instead, which caches the result
  on a terminal reference so `protocol: :auto` images render with the
  detected protocol automatically.
  """
  @spec probe_terminal() :: {:ok, probe_result()} | {:error, term()}
  def probe_terminal do
    probe_with(&Native.image_probe_terminal/0)
  end

  @doc false
  # Test seam — accepts any 0-arity function that returns the same shape
  # the NIF does (`{protocol_atom, {w, h}}` on success or `{:error, _}`
  # on failure). Production callers should use `probe_terminal/0`.
  @spec probe_with((-> term())) :: {:ok, probe_result()} | {:error, term()}
  def probe_with(probe_fn) when is_function(probe_fn, 0) do
    case probe_fn.() do
      {protocol, {w, h}} when is_atom(protocol) and is_integer(w) and is_integer(h) ->
        {:ok, %{protocol: protocol, font_size: {w, h}}}

      {:error, _reason} = err ->
        err
    end
  end

  @doc """
  Probes the local terminal and caches the result on `terminal_ref`.

  When the probe succeeds, the cached protocol and font size are used for
  every `protocol: :auto` image rendered through `terminal_ref` — Kitty
  on a Kitty terminal, halfblocks on a basic terminal, etc. When it
  fails (no TTY, no response), the cache stays empty and `:auto` images
  fall back to halfblocks. Either way this is a one-shot opt-in: call it
  once at app start, typically right after acquiring the terminal
  reference.

      ExRatatui.run(fn terminal ->
        ExRatatui.Image.auto_local_protocol(terminal)
        # ...
      end)

  Returns `:ok` on success, `{:error, reason}` if the probe failed (the
  cache is untouched in that case). Per-image explicit protocol choices
  at `ExRatatui.Image.new/2` are always honored regardless of the probe.
  """
  @spec auto_local_protocol(reference()) :: :ok | {:error, term()}
  def auto_local_protocol(terminal_ref) when is_reference(terminal_ref) do
    auto_local_protocol_with(terminal_ref, &Native.image_probe_terminal/0)
  end

  @doc false
  # Test seam mirroring `probe_with/1`.
  @spec auto_local_protocol_with(reference(), (-> term())) :: :ok | {:error, term()}
  def auto_local_protocol_with(terminal_ref, probe_fn)
      when is_reference(terminal_ref) and is_function(probe_fn, 0) do
    case probe_with(probe_fn) do
      {:ok, %{protocol: protocol, font_size: {w, h}}} ->
        Native.terminal_set_local_probe(terminal_ref, protocol, {w, h})
        :ok

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Predicts the rendered output pixel dimensions for an image, given the
  cell area it'll be drawn into.

  Mirrors ratatui-image's `Resize::needs_resize_pixels` + the
  `fit_area_proportionally` helper byte-for-byte (no drift). Useful for
  status panels in demos, layout decisions where you want to size sibling
  widgets relative to where the image will actually render, or
  understanding *why* `:fit` and `:crop` produce identical output when the
  source image is smaller than the target area on both axes.

  ## Inputs

    * `source` — the source image's pixel dimensions as `{width, height}`
      (same as `dimensions/1` returns).
    * `cell_area` — the render area in **cells**, as `{cols, rows}`.
    * `font_size` — the terminal's cell pixel size, as `{width, height}`.
      Get this from `probe_terminal/0` or default to `{10, 20}` (which
      matches `Picker::halfblocks`).
    * `resize` — one of `:fit` / `:crop` / `:scale`.

  Returns `{width_px, height_px}` for the rendered pixel size.

  ## The Fit/Crop no-upscale clamp

  Both `:fit` and `:crop` clamp output to the source image's natural
  pixel size — they never upscale. This means a 400×300 source rendered
  into an 800×500 target stays at 400×300 anchored at the corner. Only
  `:scale` upscales aspect-preservingly to fill the area. See the
  [Images guide](images.md) for the full rationale.

      iex> ExRatatui.Image.render_size({400, 300}, {80, 24}, {10, 20}, :fit)
      {400, 300}
      iex> ExRatatui.Image.render_size({400, 300}, {80, 24}, {10, 20}, :scale)
      {640, 480}
      iex> ExRatatui.Image.render_size({2000, 1000}, {80, 24}, {10, 20}, :fit)
      {800, 400}
  """
  @spec render_size(
          {pos_integer(), pos_integer()},
          {pos_integer(), pos_integer()},
          {pos_integer(), pos_integer()},
          resize()
        ) :: {pos_integer(), pos_integer()}
  def render_size({img_w, img_h}, {cols, rows}, {fw, fh}, resize)
      when img_w > 0 and img_h > 0 and cols > 0 and rows > 0 and fw > 0 and fh > 0 do
    target_w = cols * fw
    target_h = rows * fh

    case resize do
      :fit ->
        fit_area_proportionally(img_w, img_h, min(target_w, img_w), min(target_h, img_h))

      :crop ->
        {min(img_w, target_w), min(img_h, target_h)}

      :scale ->
        fit_area_proportionally(img_w, img_h, target_w, target_h)
    end
  end

  # Verbatim translation of ratatui-image's fit_area_proportionally.
  # Picks the largest aspect-preserving rect that fits inside
  # (nwidth, nheight). u16::MAX clamping omitted — Elixir doesn't have
  # the same overflow concern.
  defp fit_area_proportionally(width, height, nwidth, nheight) do
    wratio = nwidth / width
    hratio = nheight / height
    ratio = min(wratio, hratio)

    nw = max(round(width * ratio), 1)
    nh = max(round(height * ratio), 1)
    {nw, nh}
  end
end
