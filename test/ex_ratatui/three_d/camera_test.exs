defmodule ExRatatui.ThreeD.CameraTest do
  use ExUnit.Case, async: true

  alias ExRatatui.ThreeD.Camera

  doctest ExRatatui.ThreeD.Camera

  describe "orbit/3" do
    test "yaw rotates around the target keeping the radius" do
      camera = %Camera{position: {0.0, 0.0, 5.0}, target: {0.0, 0.0, 0.0}}
      %Camera{position: {x, y, z}} = Camera.orbit(camera, :math.pi() / 2, 0.0)

      assert_in_delta x, -5.0, 1.0e-4
      assert_in_delta y, 0.0, 1.0e-4
      assert_in_delta z, 0.0, 1.0e-4
    end

    test "clamps pitch near the top pole" do
      camera = %Camera{position: {0.0, 0.0, 5.0}, target: {0.0, 0.0, 0.0}}
      %Camera{position: {_, y, _}} = Camera.orbit(camera, 0.0, -10.0)

      # clamped to phi = 0.05, so y ~ radius * cos(0.05), near +radius
      assert y > 4.0
    end

    test "clamps pitch near the bottom pole" do
      camera = %Camera{position: {0.0, 0.0, 5.0}, target: {0.0, 0.0, 0.0}}
      %Camera{position: {_, y, _}} = Camera.orbit(camera, 0.0, 10.0)

      # clamped to phi = pi - 0.05, so y ~ radius * cos(pi - 0.05), near -radius
      assert y < -4.0
    end
  end

  describe "zoom/2" do
    test "positive delta moves the camera farther from the target" do
      camera = %Camera{position: {0.0, 0.0, 5.0}, target: {0.0, 0.0, 0.0}}
      %Camera{position: {x, y, z}} = Camera.zoom(camera, 2.0)

      assert_in_delta x, 0.0, 1.0e-6
      assert_in_delta y, 0.0, 1.0e-6
      assert_in_delta z, 7.0, 1.0e-6
    end

    test "distance is clamped to the minimum radius" do
      camera = %Camera{position: {0.0, 0.0, 1.0}, target: {0.0, 0.0, 0.0}}
      %Camera{position: {_, _, z}} = Camera.zoom(camera, -100.0)
      assert_in_delta z, 0.5, 1.0e-6
    end

    test "a camera sitting on its target does not divide by zero" do
      camera = %Camera{position: {0.0, 0.0, 0.0}, target: {0.0, 0.0, 0.0}}
      %Camera{position: {x, y, z}} = Camera.zoom(camera, 1.0)

      assert_in_delta x, 0.0, 1.0e-6
      assert_in_delta y, 0.0, 1.0e-6
      assert_in_delta z, 0.0, 1.0e-6
    end
  end
end
