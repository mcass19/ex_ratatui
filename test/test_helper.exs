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

# Opening the real terminal puts it in raw mode on the alternate screen: on a
# developer's machine that is the terminal the suite runs in, and on CI it
# fails, so a test going through it has two outcomes. Make it fail the same
# way everywhere; tests that need a terminal use `test_mode` or
# `ExRatatui.init_test_terminal/2`, and run_test.exs swaps in its own.
Application.put_env(:ex_ratatui, :init_terminal_fn, fn _focus_events?, _mouse_capture? ->
  {:error, :no_terminal_in_tests}
end)

# examples_test.exs runs the Erlang example's EUnit suite, and Mix prunes
# OTP applications that aren't dependencies from the code path.
Mix.ensure_application!(:eunit)

# Priority signals (`:erlang.link/2`, `[:priority]` monitors) arrived in
# OTP 28; the Server falls back to FIFO close on older releases.
otp_excludes = if String.to_integer(System.otp_release()) < 28, do: [:otp28], else: []

# ExUnit's 100 ms default for `assert_receive` is tight for messages that
# cross a few processes on a loaded CI runner. A passing assertion returns
# as soon as the message arrives, so the longer wait only costs time on a
# failure.
ExUnit.start(exclude: [:distributed, :slow] ++ otp_excludes, assert_receive_timeout: 1_000)
