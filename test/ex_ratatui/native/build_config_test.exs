defmodule ExRatatui.Native.BuildConfigTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Native.BuildConfig

  describe "truthy?/1" do
    test "accepts the documented truthy env var values" do
      assert BuildConfig.truthy?("1")
      assert BuildConfig.truthy?("true")
    end

    test "rejects everything else, including an unset variable" do
      refute BuildConfig.truthy?("0")
      refute BuildConfig.truthy?("false")
      refute BuildConfig.truthy?("yes")
      refute BuildConfig.truthy?(nil)
    end
  end

  describe "force_build?/3" do
    test "force_build_all wins over the per-app config and the env var" do
      assert BuildConfig.force_build?(true, false, nil)
      assert BuildConfig.force_build?(true, nil, "0")
    end

    test "per-app config takes effect when force_build_all is off" do
      assert BuildConfig.force_build?(false, true, nil)
    end

    test "per-app config of false wins over a truthy env var" do
      refute BuildConfig.force_build?(false, false, "true")
    end

    test "falls back to the env var when the per-app config is absent" do
      assert BuildConfig.force_build?(false, nil, "1")
      assert BuildConfig.force_build?(false, nil, "true")
      refute BuildConfig.force_build?(false, nil, nil)
      refute BuildConfig.force_build?(false, nil, "false")
    end

    test "ignores a non-boolean per-app config and falls back to the env var" do
      assert BuildConfig.force_build?(false, "true", "1")
      refute BuildConfig.force_build?(false, "true", nil)
    end
  end
end
