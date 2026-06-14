defmodule ExRatatui.ThreeD.Material do
  @moduledoc """
  Phong surface material for a 3D object.

  ## Fields

    * `:color` - base `{r, g, b}` color, channels 0-255
    * `:ambient` - ambient reflection coefficient (defaults to `0.1`)
    * `:diffuse` - diffuse reflection coefficient (defaults to `0.8`)
    * `:specular` - specular reflection coefficient (defaults to `0.5`)
    * `:shininess` - specular exponent (defaults to `32.0`)

  ## Examples

      iex> %ExRatatui.ThreeD.Material{}
      %ExRatatui.ThreeD.Material{
        color: {200, 200, 200},
        ambient: 0.1,
        diffuse: 0.8,
        specular: 0.5,
        shininess: 32.0
      }

      iex> %ExRatatui.ThreeD.Material{color: {100, 150, 255}}.color
      {100, 150, 255}
  """

  @type rgb :: {0..255, 0..255, 0..255}

  @type t :: %__MODULE__{
          color: rgb(),
          ambient: float(),
          diffuse: float(),
          specular: float(),
          shininess: float()
        }

  defstruct color: {200, 200, 200},
            ambient: 0.1,
            diffuse: 0.8,
            specular: 0.5,
            shininess: 32.0
end
