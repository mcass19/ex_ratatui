defmodule ExRatatui.Server.ProbeImageProtocolTest do
  @moduledoc """
  Covers the `:probe_image_protocol` runtime opt added to `mount/1`.

  The opt is honored only on the `:local` transport (CellSession
  forces halfblocks; SSH / Distributed surface their own
  `:image_protocol` session opt). When the opt is set and `test_mode`
  is nil, the runtime runs `Picker::from_query_stdio` once after mount
  via `ExRatatui.Image.auto_local_protocol/1`. The probe soft-fails
  if no TTY is available — it never crashes the server.
  """
  use ExUnit.Case, async: true

  alias ExRatatui.Server

  describe "maybe_probe_image_protocol/3" do
    test "is a no-op when the opt is false" do
      assert :ok =
               Server.maybe_probe_image_protocol(:fake_ref, %{probe_image_protocol: false}, nil)
    end

    test "is a no-op in test_mode regardless of the opt" do
      assert :ok =
               Server.maybe_probe_image_protocol(
                 :fake_ref,
                 %{probe_image_protocol: true},
                 {80, 24}
               )
    end

    test "soft-runs the probe when the opt is true and test_mode is nil" do
      # The Application-configured probe fake (`test_helper.exs`) makes
      # this fire the wrapper without touching real stdio; the wrapper
      # always returns `:ok` regardless of whether the inner probe
      # succeeded or failed (errors are swallowed by design — the cache
      # just stays empty).
      terminal = ExRatatui.init_test_terminal(20, 5)
      on_exit(fn -> ExRatatui.Native.restore_terminal(terminal) end)

      assert :ok = Server.maybe_probe_image_protocol(terminal, %{probe_image_protocol: true}, nil)
    end
  end
end
