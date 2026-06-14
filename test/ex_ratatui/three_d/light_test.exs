defmodule ExRatatui.ThreeD.LightTest do
  use ExUnit.Case, async: true

  alias ExRatatui.ThreeD.Light

  doctest ExRatatui.ThreeD.Light

  test "ambient/1 defaults intensity to 1.0" do
    assert %Light{type: :ambient, intensity: 1.0} = Light.ambient({10, 20, 30})
  end

  test "directional/3 accepts an intensity option" do
    light = Light.directional({-1.0, 0.0, 0.0}, {255, 255, 255}, intensity: 0.4)
    assert light.intensity == 0.4
  end

  test "point/3 accepts an intensity option" do
    light = Light.point({0.0, 5.0, 0.0}, {255, 255, 255}, intensity: 2.0)
    assert light.intensity == 2.0
  end
end
