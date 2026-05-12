# ratatui-image's `Picker::from_query_stdio()` writes an escape to
# stdout and waits up to 2 seconds for the terminal's reply on stdin.
# Under `mix test` that races with ExUnit's stdio capture and can
# queue dirty-IO scheduler threads for multiple seconds — making async
# test runs look like they hang. Override the probe with a fast fake
# in every test by default; tests that want to exercise specific probe
# outcomes can override the config locally.
Application.put_env(:ex_ratatui, :image_probe_fn, fn -> {:error, :no_probe_in_tests} end)

ExUnit.start(exclude: [:distributed, :slow])
