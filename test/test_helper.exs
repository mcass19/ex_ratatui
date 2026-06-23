# ratatui-image's `Picker::from_query_stdio()` writes an escape to
# stdout and waits up to 2 seconds for the terminal's reply on stdin.
# Under `mix test` that races with ExUnit's stdio capture and can
# queue dirty-IO scheduler threads for multiple seconds — making async
# test runs look like they hang. Override the probe with a fast fake
# in every test by default; tests that want to exercise specific probe
# outcomes can override the config locally.
Application.put_env(:ex_ratatui, :image_probe_fn, fn -> {:error, :no_probe_in_tests} end)

# The local-input handoff parks the BEAM's `:user_drv_reader` so crossterm
# can own the tty (see ExRatatui.LocalInput). Under `mix test` that reader
# is the suite's own shell reader — leave it alone globally and exercise the
# handoff against a fake reader in local_input_test.exs.
Application.put_env(:ex_ratatui, :detach_local_input, false)

ExUnit.start(exclude: [:distributed, :slow])
