defmodule ExRatatui.Widgets.Image do
  @moduledoc """
  A widget that renders a real image (PNG/JPEG/GIF/WebP/BMP) inside a TUI.

  Image is a **stateful** widget: the decoded image data and the active
  protocol encoder live in Rust via a `ResourceArc`. Construct the state
  with `ExRatatui.Image.new/2`, which returns the widget struct ready to
  drop into a render tree.

  ```elixir
  {:ok, picture} = ExRatatui.Image.new(File.read!("priv/slides/cover.png"))

  def view(model, area) do
    [{picture, area}]
  end
  ```

  The widget itself is just a wrapper around the `:state` reference; render
  options (`:resize`, `:protocol`, `:background`) are set once at
  `ExRatatui.Image.new/2` and stored on the resource. To change them, build a
  new image handle.

  See `ExRatatui.Image` for the construction API and the protocol/transport
  fallback rules.

  ## Fields

    * `:state` - the image state reference returned by `ExRatatui.Image.new/2` (required)
  """

  @type t :: %__MODULE__{state: reference() | nil}

  defstruct state: nil
end
