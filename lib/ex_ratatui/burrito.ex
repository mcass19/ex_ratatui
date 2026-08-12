defmodule ExRatatui.Burrito do
  @moduledoc """
  Runtime support for TUIs packaged as single-file binaries with
  [Burrito](https://github.com/burrito-elixir/burrito).

  The CLI module scaffolded by `mix ex_ratatui.gen.burrito` is a thin shim
  that delegates to `main/3`, so fixes to the entry-point protocol ship
  with ex_ratatui upgrades instead of freezing in generated consumer code.
  `verify_linux_nif/1` is a release step that turns the most common
  packaging mistake — building the linux target without `TARGET_ABI=musl`
  — into an immediate build error instead of a shipped-broken binary.

  Nothing here references Burrito at compile time: the wrapped-binary
  check reads the `__BURRITO` environment variable the burrito wrapper
  sets when launching the payload, which its maintainers document as the
  supported detection mechanism, so ex_ratatui needs no burrito
  dependency.
  """

  @doc """
  Entry point for a burrito-wrapped TUI.

  Boots `tui_module` (any module using `ExRatatui.App`), waits for it to
  exit, then stops the VM with a matching exit code so the wrapper
  returns control to the shell: 0 after a clean exit, 1 when the TUI
  crashes, fails to start (no TTY, NIF/host mismatch), or the entry point
  itself raises.

  A no-op unless running inside a burrito-wrapped binary — the supervised
  task also starts under the consumer's `mix test` and `iex -S mix`, and
  must not take over those sessions. A `--version` flag anywhere in
  `argv` prints `name version` and exits 0 without a TTY; it first forces
  the NIF `dlopen`, so a precompiled-NIF/host mismatch fails loudly
  rather than silently exiting 0.

  ## Options

    * `:name` (required) — the binary's name, used in `--version` output
      and error messages.
    * `:version` — the version string `--version` prints.
    * `:halt` — 1-arity function invoked with the exit code instead of
      `System.stop/1`; exists for tests and embedders.
  """
  @spec main(module(), [String.t()], keyword()) :: :ok
  def main(tui_module, argv, opts) do
    name = Keyword.fetch!(opts, :name)
    halt = Keyword.get(opts, :halt, &System.stop/1)

    try do
      if standalone?() do
        run(tui_module, argv, name, opts[:version], halt)
      else
        :ok
      end
    rescue
      # A raise here would otherwise kill the :temporary task without
      # reaching System.stop, hanging the wrapped binary on an idle BEAM.
      exception ->
        IO.puts(:stderr, "#{name} crashed: " <> Exception.message(exception))
        halt.(1)
    end
  end

  @doc """
  Release step that fails the build when the linux burrito target bundles
  a glibc NIF.

  Burrito's linux wrapper runs a musl runtime, so the linux target must
  bundle the musl NIF (`TARGET_ABI=musl` at `mix release` time) — a glibc
  `.so` cannot load there and the shipped binary would hang at NIF load
  on every end-user machine. Wire it between `:assemble` and
  `Burrito.wrap/1`:

      steps: [:assemble, &ExRatatui.Burrito.verify_linux_nif/1, &Burrito.wrap/1]

  A no-op unless `BURRITO_TARGET=linux`. Detection is a byte scan of the
  assembled NIF: glibc-linked ELFs embed `libc.so.6` and `GLIBC_` version
  references, musl ones reference `libc.so` alone.

  Only the NIF this build actually loads is scanned — the single path
  handed to `:erlang.load_nif/2`, which `load_from` names. `priv/native`
  is a junk drawer otherwise: rustler_precompiled never evicts the
  artifacts of earlier versions or ABIs, and a path dependency carries
  the whole directory into the release, so scanning every `.so` there
  fails on stale glibc siblings that no runtime ever opens.
  """
  @spec verify_linux_nif(Mix.Release.t(), {atom(), String.t()}) :: Mix.Release.t()
  def verify_linux_nif(release, load_from \\ ExRatatui.Native.load_from()) do
    if System.get_env("BURRITO_TARGET") == "linux" do
      {_otp_app, relative_path} = load_from

      release.path
      |> Path.join("lib/ex_ratatui-*/#{relative_path}.so")
      |> Path.wildcard()
      |> case do
        # An assembled release must contain the NIF — an empty match means
        # the layout changed and this check would otherwise silently pass
        # while verifying nothing.
        [] ->
          Mix.raise(
            "no ex_ratatui NIF found at #{release.path}/lib/ex_ratatui-*/#{relative_path}.so"
          )

        so_paths ->
          Enum.each(so_paths, &verify_musl!/1)
      end
    end

    release
  end

  defp verify_musl!(so_path) do
    bytes = File.read!(so_path)

    if String.contains?(bytes, "libc.so.6") or String.contains?(bytes, "GLIBC_") do
      Mix.raise("""
      #{Path.relative_to_cwd(so_path)} is a glibc NIF, but burrito's linux \
      wrapper runs a musl runtime — the wrapped binary would fail at NIF \
      load on every end-user machine.

      Rebuild with the musl NIF:

          TARGET_ABI=musl BURRITO_TARGET=linux MIX_ENV=prod mix release --overwrite

      TARGET_ABI only picks between precompiled NIFs, so it has no effect \
      on a locally built crate: unset EX_RATATUI_BUILD and any \
      `:force_build` rustler_precompiled config before releasing.

      If the error persists, an already compiled dependency is holding the \
      glibc NIF — wipe _build/prod/lib/ex_ratatui and rebuild.
      """)
    end
  end

  defp run(tui_module, argv, name, version, halt) do
    if "--version" in argv do
      :ok = ExRatatui.Native.ensure_loaded()
      IO.puts(String.trim("#{name} #{version}"))
      halt.(0)
    else
      run_tui(tui_module, name, halt)
    end
  end

  defp run_tui(tui_module, name, halt) do
    case tui_module.start_link([]) do
      {:ok, pid} ->
        # An abnormal TUI exit must arrive as a DOWN message — not as an
        # exit signal that kills the caller before it can set the exit
        # code, leaving the wrapped binary hanging on an idle BEAM.
        ref = Process.monitor(pid)
        Process.unlink(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, reason} -> shut_down(reason, name, halt)
        end

      {:error, reason} ->
        IO.puts(:stderr, "#{name} failed to start: #{inspect(reason)}")
        halt.(1)
    end
  end

  defp shut_down(reason, _name, halt) when reason in [:normal, :shutdown], do: halt.(0)
  defp shut_down({:shutdown, _}, _name, halt), do: halt.(0)

  defp shut_down(reason, name, halt) do
    IO.puts(:stderr, "#{name} terminated: #{inspect(reason)}")
    halt.(1)
  end

  defp standalone?, do: System.get_env("__BURRITO") != nil
end
