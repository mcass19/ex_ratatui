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
      `:auto` resolves at render time using the transport's capabilities;
      see `c:resolve_protocol/0` semantics in the design guide. Explicit
      protocols are honored except over `CellSession`-style transports
      where `:halfblocks` is forced.
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

    case Native.image_new(bytes, nif_opts) do
      ref when is_reference(ref) -> {:ok, %Widget{state: ref}}
      {:error, _reason} = err -> err
    end
  end

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
end
