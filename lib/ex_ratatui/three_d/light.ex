defmodule ExRatatui.ThreeD.Light do
  @moduledoc """
  A light source: ambient, directional, or point.

  ## Fields

    * `:type` - `:ambient`, `:directional`, or `:point`
    * `:color` - `{r, g, b}` color, channels 0-255
    * `:intensity` - scalar brightness (defaults to `1.0`)
    * `:direction` - `{x, y, z}` direction toward the light (only for `:directional`)
    * `:position` - `{x, y, z}` world position (only for `:point`)

  Prefer the constructors over building the struct by hand.

  ## Examples

      iex> light = ExRatatui.ThreeD.Light.ambient({255, 255, 255}, 0.15)
      iex> {light.type, light.color, light.intensity}
      {:ambient, {255, 255, 255}, 0.15}

      iex> light = ExRatatui.ThreeD.Light.directional({-1.0, -1.0, -1.0}, {255, 255, 255})
      iex> {light.type, light.direction, light.intensity}
      {:directional, {-1.0, -1.0, -1.0}, 1.0}

      iex> light = ExRatatui.ThreeD.Light.point({2.0, 3.0, 2.0}, {255, 220, 180})
      iex> {light.type, light.position}
      {:point, {2.0, 3.0, 2.0}}
  """

  @type rgb :: {0..255, 0..255, 0..255}
  @type vec3 :: {number(), number(), number()}
  @type kind :: :ambient | :directional | :point

  @type t :: %__MODULE__{
          type: kind(),
          color: rgb(),
          intensity: float(),
          direction: vec3() | nil,
          position: vec3() | nil
        }

  defstruct type: :ambient,
            color: {255, 255, 255},
            intensity: 1.0,
            direction: nil,
            position: nil

  @doc "Constant ambient illumination."
  @spec ambient(rgb(), number()) :: t()
  def ambient(color, intensity \\ 1.0) do
    %__MODULE__{type: :ambient, color: color, intensity: intensity}
  end

  @doc """
  A directional light. `direction` points toward the light source.

  Options: `:intensity` (defaults to `1.0`).
  """
  @spec directional(vec3(), rgb(), keyword()) :: t()
  def directional(direction, color, opts \\ []) do
    %__MODULE__{
      type: :directional,
      direction: direction,
      color: color,
      intensity: Keyword.get(opts, :intensity, 1.0)
    }
  end

  @doc """
  A point light at `position`.

  Options: `:intensity` (defaults to `1.0`).
  """
  @spec point(vec3(), rgb(), keyword()) :: t()
  def point(position, color, opts \\ []) do
    %__MODULE__{
      type: :point,
      position: position,
      color: color,
      intensity: Keyword.get(opts, :intensity, 1.0)
    }
  end
end
