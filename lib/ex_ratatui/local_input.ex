defmodule ExRatatui.LocalInput do
  @moduledoc false
  # Hands the local controlling terminal off to the Rust/crossterm reader
  # for the duration of a TUI session.
  #
  # On a `:local` transport, ExRatatui reads key events through crossterm
  # in a NIF, which on Unix reads the controlling terminal directly. But
  # the BEAM has its own terminal reader too: on OTP 26+ the `prim_tty`
  # reader process (registered as `:user_drv_reader`) sits in a `read()`
  # loop on the same tty — whether started from `iex`, `elixir foo.exs`,
  # or a shell-attached release. Two readers on one terminal means the
  # kernel hands each keystroke to whichever `read()` wins, so under fast
  # input some bytes never reach the TUI. They surface dropped, or land at
  # the shell prompt once the TUI exits.
  #
  # We resolve it with the same mechanism OTP itself uses to hand the tty
  # off on SIGTSTP: `prim_tty`'s `disable`/`enable` reader protocol. While
  # disabled the reader parks at a receive boundary and stops calling
  # `read()`, so crossterm gets every byte. Reattaching on teardown brings
  # the shell back — unlike killing the reader, which leaves the tty in
  # cooked mode and cannot be undone. termios stays raw throughout, so the
  # handoff is invisible to the shell.
  #
  # When no reader is registered — a release booted with `-noinput`, OTP
  # older than 26, or stdin that is not a tty — every entry point is a
  # no-op. It can be disabled wholesale with
  # `config :ex_ratatui, detach_local_input: false`.

  @default_reader :user_drv_reader
  @default_timeout 1_000

  @typedoc "Opaque handle returned by `detach/0`, passed back to `reattach/1`."
  @type handle :: {:detached, pid()} | :not_detached

  @doc """
  Parks the BEAM's local terminal reader so crossterm owns the tty.

  Returns a handle to pass to `reattach/1` on teardown. A no-op (returning
  `:not_detached`) when detaching is disabled or no reader is registered.
  """
  @spec detach() :: handle()
  def detach do
    if enabled?() do
      detach(reader_name())
    else
      :not_detached
    end
  end

  @doc false
  # Lower-level seam: resolves an explicit reader (name or pid), bypassing
  # the app-env gate. Used directly in tests against a fake reader.
  @spec detach(atom() | pid() | nil) :: handle()
  def detach(nil), do: :not_detached
  def detach(name) when is_atom(name), do: detach(Process.whereis(name))

  def detach(pid) when is_pid(pid) do
    case toggle(pid, :disable) do
      :ok -> {:detached, pid}
      {:error, _reason} -> :not_detached
    end
  end

  @doc """
  Resumes a reader previously parked by `detach/0`, restoring shell input.
  """
  @spec reattach(handle()) :: :ok
  def reattach({:detached, pid}) do
    _ = toggle(pid, :enable)
    :ok
  end

  def reattach(:not_detached), do: :ok

  # Speaks the `prim_tty` reader's request protocol: alias-monitor the
  # reader, send the request, await its ack. A dead or unresponsive reader
  # degrades to `{:error, _}` rather than blocking the caller.
  defp toggle(pid, message) do
    ref = Process.monitor(pid, alias: :reply_demonitor)
    send(pid, {ref, message})

    receive do
      {^ref, :ok} -> :ok
      {:DOWN, ^ref, :process, _pid, reason} -> {:error, reason}
    after
      timeout() ->
        Process.demonitor(ref, [:flush])
        {:error, :timeout}
    end
  end

  defp enabled?, do: Application.get_env(:ex_ratatui, :detach_local_input, true)
  defp reader_name, do: Application.get_env(:ex_ratatui, :local_input_reader, @default_reader)
  defp timeout, do: Application.get_env(:ex_ratatui, :local_input_timeout, @default_timeout)
end
