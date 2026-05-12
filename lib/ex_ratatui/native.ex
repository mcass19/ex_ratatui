defmodule ExRatatui.Native do
  @moduledoc false

  @otp_app :ex_ratatui
  @load_lock {__MODULE__, :nif_load_lock}
  @loaded_key {__MODULE__, :nif_loaded}
  @nif_functions [
    init_terminal: 0,
    restore_terminal: 1,
    terminal_size: 0,
    draw_frame: 2,
    poll_event: 1,
    layout_split: 3,
    init_test_terminal: 2,
    get_buffer_content: 1,
    text_input_new: 0,
    text_input_handle_key: 2,
    text_input_get_value: 1,
    text_input_set_value: 2,
    text_input_cursor: 1,
    text_input_snapshot: 1,
    session_new: 2,
    session_close: 1,
    session_draw: 2,
    session_take_output: 1,
    session_feed_input: 2,
    session_reset_parser: 1,
    session_resize: 3,
    session_size: 1,
    cell_session_new: 2,
    cell_session_close: 1,
    cell_session_draw: 2,
    cell_session_take_cells: 1,
    cell_session_take_cells_diff: 1,
    cell_session_feed_input: 2,
    cell_session_reset_parser: 1,
    cell_session_resize: 3,
    cell_session_size: 1,
    textarea_new: 0,
    textarea_handle_key: 3,
    textarea_get_value: 1,
    textarea_set_value: 2,
    textarea_cursor: 1,
    textarea_snapshot: 1,
    textarea_line_count: 1,
    image_new: 2,
    image_dimensions: 1,
    image_snapshot: 1,
    image_probe_terminal: 0,
    session_set_image_protocol: 2,
    session_set_image_font_size: 2,
    terminal_set_image_protocol: 2,
    terminal_set_local_probe: 3
  ]

  version = Mix.Project.config()[:version]

  precompiled_opts = [
    otp_app: @otp_app,
    crate: "ex_ratatui",
    base_url: "https://github.com/mcass19/ex_ratatui/releases/download/v#{version}",
    force_build: System.get_env("EX_RATATUI_BUILD") in ["1", "true"],
    version: version,
    targets: ~w(
      aarch64-apple-darwin
      aarch64-unknown-linux-gnu
      aarch64-unknown-linux-musl
      arm-unknown-linux-gnueabihf
      riscv64gc-unknown-linux-gnu
      x86_64-apple-darwin
      x86_64-pc-windows-gnu
      x86_64-pc-windows-msvc
      x86_64-unknown-linux-gnu
      x86_64-unknown-linux-musl
    ),
    nif_versions: ["2.16", "2.17"]
  ]

  precompiled_opts =
    if Application.compile_env(
         :rustler_precompiled,
         :force_build_all,
         System.get_env("RUSTLER_PRECOMPILED_FORCE_BUILD_ALL") in ["1", "true"]
       ) do
      Keyword.put(precompiled_opts, :force_build, true)
    else
      Keyword.put_new(
        precompiled_opts,
        :force_build,
        Application.compile_env(:rustler_precompiled, [:force_build, @otp_app])
      )
    end

  case RustlerPrecompiled.__using__(__MODULE__, precompiled_opts) do
    {:force_build, rustler_opts} ->
      env = Application.compile_env(@otp_app, __MODULE__, [])
      config = Rustler.Compiler.compile_crate(@otp_app, env, rustler_opts)

      for resource <- config.external_resources do
        @external_resource resource
      end

      @load_from config.load_from
      @load_data config.load_data
      @load_data_fun config.load_data_fun

    {:ok, config} ->
      @load_from config.load_from
      @load_data config.load_data
      @load_data_fun nil

    {:error, precomp_error} ->
      raise precomp_error
  end

  @doc false
  def ensure_loaded do
    if loaded?() do
      :ok
    else
      :global.trans(@load_lock, &ensure_loaded_once/0)
    end
  end

  @doc false
  def loaded?, do: :persistent_term.get(@loaded_key, false)

  defp mark_loaded, do: :persistent_term.put(@loaded_key, true)

  defp ensure_loaded_once do
    if loaded?() do
      :ok
    else
      load_nif_once()
    end
  end

  defp load_nif_once do
    case load_nif() do
      :ok -> mark_loaded_and_return_ok()
      {:error, {:reload, _reason}} -> mark_loaded_and_return_ok()
      {:error, {:upgrade, _reason}} -> mark_loaded_and_return_ok()
      {:error, reason} -> raise "failed to load ExRatatui NIF: #{inspect(reason)}"
    end
  end

  defp mark_loaded_and_return_ok do
    mark_loaded()
    :ok
  end

  defp load_nif do
    :code.purge(__MODULE__)

    {otp_app, path} = @load_from

    load_path =
      otp_app
      |> Application.app_dir(path)
      |> to_charlist()

    :erlang.load_nif(load_path, load_data())
  end

  if @load_data_fun do
    defp load_data do
      {module, function} = @load_data_fun
      apply(module, function, [])
    end
  else
    defp load_data, do: @load_data
  end

  defp dispatch(name, args) do
    :ok = ensure_loaded()
    :erlang.apply(__MODULE__, name, args)
  end

  for {name, arity} <- @nif_functions do
    args = Macro.generate_arguments(arity, __MODULE__)

    @doc false
    def unquote(name)(unquote_splicing(args)) do
      dispatch(unquote(name), [unquote_splicing(args)])
    end
  end
end
