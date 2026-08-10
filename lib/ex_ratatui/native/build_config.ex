defmodule ExRatatui.Native.BuildConfig do
  @moduledoc false

  # Resolves whether the Rust NIF should be built from source instead of
  # downloading a precompiled artifact.
  #
  # Kept in its own module so the precedence rules are plain functions that can
  # be unit tested — the call site in `ExRatatui.Native` runs at compile time,
  # where the inputs come from `Application.compile_env/3` and `System.get_env/1`
  # and cannot be varied from a test.

  @truthy ["1", "true"]

  @doc false
  @spec truthy?(String.t() | nil) :: boolean()
  def truthy?(value), do: value in @truthy

  @doc false
  @spec force_build?(term(), term(), String.t() | nil) :: boolean()
  def force_build?(force_build_all?, per_app_config, env_value) do
    cond do
      # `:force_build_all` (or RUSTLER_PRECOMPILED_FORCE_BUILD_ALL) wins over
      # everything, per the rustler_precompiled contract.
      force_build_all? ->
        true

      # `config :rustler_precompiled, :force_build, ex_ratatui: true` — the
      # per-application override documented by rustler_precompiled.
      is_boolean(per_app_config) ->
        per_app_config

      # Project-specific fallback for people who prefer an env var.
      true ->
        truthy?(env_value)
    end
  end
end
