# Example: interactive image rendering demo, runnable on every transport.
#
# Run modes:
#   mix run examples/image_demo.exs                # local terminal
#   mix run --no-halt examples/image_demo.exs --ssh       # serve over SSH
#   mix run --no-halt examples/image_demo.exs --ssh 2223  # custom port
#   elixir --sname app --cookie demo -S mix run --no-halt \
#     examples/image_demo.exs --distributed         # serve over Erlang distribution
#
# Controls (all transports):
#   p — cycle protocol (auto / halfblocks / kitty / sixel / iterm2)
#   r — cycle resize  (fit / crop / scale)
#   q — quit
#
# Image source (all transports):
#   - IMAGE_PATH env var, if set, points to a local image file
#   - otherwise picsum.photos/400/300 is fetched once at startup
#   - if that fails too, falls back to a 67-byte 1×1 PNG so the demo
#     still runs offline (just visually boring)
#
# How each transport handles the image:
#
#   - Local: `probe_image_protocol: true` from mount/1 fires the
#     terminal capability probe so `:auto` resolves to whatever native
#     protocol the terminal supports. Falls back to halfblocks if the
#     probe can't complete.
#
#   - SSH: the daemon is started with `image_protocol: :auto` and
#     `image_font_size: {10, 20}` — sane defaults for a Kitty/Ghostty
#     client. Override `IMAGE_PROTOCOL` / `IMAGE_FONT_W` / `IMAGE_FONT_H`
#     env vars for other clients.
#
#   - Distributed: the listener does not pre-configure the local
#     terminal — the *connecting* node's terminal capabilities matter,
#     so let `ExRatatui.Distributed.attach/3` callers pass their own
#     `image_protocol:` / `image_font_size:` opts. The example below
#     shows the suggested attach call after the listener starts.

alias ExRatatui.Event
alias ExRatatui.Image
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Paragraph}

defmodule ImageDemo do
  use ExRatatui.App

  alias ExRatatui.Image

  @protocols [:auto, :halfblocks, :kitty, :sixel, :iterm2]
  @resizes [:fit, :crop, :scale]

  @impl true
  def mount(_opts) do
    bytes = load_image_bytes()
    {:ok, image} = Image.new(bytes, protocol: :auto, resize: :scale)

    {w, h} = Image.dimensions(image)

    # `probe_image_protocol: true` asks the runtime to run the terminal
    # capability probe right after mount — `:auto` images then render
    # via the detected protocol (Kitty / Sixel / iTerm2 / Halfblocks).
    {:ok,
     %{
       image: image,
       image_bytes: bytes,
       protocol: :auto,
       resize: :scale,
       image_size: {w, h},
       probe: probe_string()
     }, probe_image_protocol: true}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [image_area, status_area, help_area] =
      Layout.split(area, :vertical, [{:min, 0}, {:length, 4}, {:length, 3}])

    {iw, ih} = state.image_size
    {fw, fh} = state.probe

    # render_size expects positive integers; the probe falls back to
    # {0, 0} when probing fails. Substitute the Picker::halfblocks
    # default (10, 20) so the math stays meaningful in either case.
    font_size = if fw > 0 and fh > 0, do: state.probe, else: {10, 20}

    {rw, rh} =
      Image.render_size(
        state.image_size,
        {image_area.width, image_area.height},
        font_size,
        state.resize
      )

    upscale_tag =
      cond do
        # No-upscale clamp kicked in (source < target on both axes).
        state.resize in [:fit, :crop] and rw == iw and rh == ih -> " (clamped to source)"
        # :scale always upscales when source < target.
        true -> ""
      end

    status = %Paragraph{
      text: """
        protocol: #{inspect(state.protocol)}   resize: #{inspect(state.resize)}   tty: #{fw}x#{fh}
        image: #{iw}x#{ih} px   area: #{image_area.width}x#{image_area.height} cells   render: #{rw}x#{rh} px#{upscale_tag}\
      """,
      style: %Style{fg: :light_cyan, modifiers: [:bold]},
      block: %Block{borders: [:all], border_type: :rounded}
    }

    help = %Paragraph{
      text: "  p = cycle protocol   r = cycle resize   q = quit",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:top], border_style: %Style{fg: :dark_gray}}
    }

    [
      {state.image, image_area},
      {status, status_area},
      {help, help_area}
    ]
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state) do
    {:stop, state}
  end

  def handle_event(%Event.Key{code: "p", kind: "press"}, state) do
    {:noreply, advance(state, :protocol, @protocols)}
  end

  def handle_event(%Event.Key{code: "r", kind: "press"}, state) do
    {:noreply, advance(state, :resize, @resizes)}
  end

  def handle_event(_event, state), do: {:noreply, state}

  # -- internals -------------------------------------------------------

  defp advance(state, key, options) do
    idx = Enum.find_index(options, &(&1 == state[key])) || 0
    next = Enum.at(options, rem(idx + 1, length(options)))

    {:ok, image} =
      Image.new(state.image_bytes,
        protocol: protocol_for(state, key, next),
        resize: resize_for(state, key, next)
      )

    state |> Map.put(key, next) |> Map.put(:image, image)
  end

  defp protocol_for(_state, :protocol, next), do: next
  defp protocol_for(state, _, _), do: state.protocol

  defp resize_for(_state, :resize, next), do: next
  defp resize_for(state, _, _), do: state.resize

  defp probe_string do
    case ExRatatui.Image.probe_terminal() do
      {:ok, %{font_size: {w, h}}} -> {w, h}
      _ -> {0, 0}
    end
  end

  defp load_image_bytes do
    case System.get_env("IMAGE_PATH") do
      nil -> fetch_picsum_or_fallback()
      path -> File.read!(path)
    end
  end

  defp fetch_picsum_or_fallback do
    case fetch("https://picsum.photos/400/300") do
      {:ok, bytes} -> bytes
      _ -> fallback_png()
    end
  end

  defp fetch(url) do
    :inets.start()
    :ssl.start()

    case :httpc.request(:get, {String.to_charlist(url), []}, [{:timeout, 5_000}],
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, _headers, body}} when status in 200..299 -> {:ok, body}
      other -> {:error, other}
    end
  rescue
    _ -> {:error, :exception}
  end

  defp fallback_png do
    Base.decode64!(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
    )
  end
end

defmodule ImageDemo.Runner do
  @moduledoc false

  def main(argv) do
    case argv do
      ["--ssh" | rest] -> run_ssh(rest)
      ["--distributed"] -> run_distributed()
      _ -> run_local()
    end
  end

  defp run_local do
    {:ok, pid} = ImageDemo.start_link([])
    wait_for(pid)
  end

  defp run_ssh(rest) do
    port =
      case rest do
        [port_str] -> String.to_integer(port_str)
        _ -> 2222
      end

    {protocol, font_size} = ssh_image_opts()

    {:ok, daemon} =
      ExRatatui.SSH.Daemon.start_link(
        mod: ImageDemo,
        name: nil,
        port: port,
        image_protocol: protocol,
        image_font_size: font_size,
        system_dir: shared_host_key_dir(),
        auth_methods: ~c"password",
        user_passwords: [{~c"demo", ~c"demo"}]
      )

    IO.puts("""

    \e[36mImage demo over SSH\e[0m — listening on port #{port}

    Connect:

        ssh demo@localhost -p #{port}

    Password: \e[1mdemo\e[0m
    Sessions render with image_protocol: #{inspect(protocol)}, font_size: #{inspect(font_size)}.
    Override with IMAGE_PROTOCOL / IMAGE_FONT_W / IMAGE_FONT_H env vars.

    Ctrl-C twice to stop the daemon.
    """)

    wait_for(daemon)
  end

  defp run_distributed do
    unless Node.alive?() do
      IO.puts(:stderr, """

      \e[31mError:\e[0m This node is not distributed.
      Start it with --sname or --name:

          elixir --sname app --cookie demo -S mix run --no-halt \\
            examples/image_demo.exs --distributed
      """)

      System.halt(1)
    end

    {:ok, pid} = ExRatatui.Distributed.Listener.start_link(mod: ImageDemo)

    IO.puts("""

    \e[36mImage demo over Erlang Distribution\e[0m

    This node: \e[1m#{Node.self()}\e[0m

    From another node (same cookie), run one of:

        # Halfblocks default — safe and works everywhere
        ExRatatui.Distributed.attach(#{inspect(Node.self())}, ImageDemo)

        # Kitty/Ghostty client with accurate scaling
        ExRatatui.Distributed.attach(#{inspect(Node.self())}, ImageDemo,
          image_protocol: :kitty,
          image_font_size: {10, 20}
        )

    Ctrl-C twice to stop the listener.
    """)

    wait_for(pid)
  end

  defp ssh_image_opts do
    protocol =
      case System.get_env("IMAGE_PROTOCOL") do
        nil -> :auto
        s -> String.to_existing_atom(s)
      end

    font_size = {
      String.to_integer(System.get_env("IMAGE_FONT_W") || "10"),
      String.to_integer(System.get_env("IMAGE_FONT_H") || "20")
    }

    {protocol, font_size}
  end

  defp shared_host_key_dir do
    [System.tmp_dir!(), "ex_ratatui_example_host_keys"]
    |> Path.join()
    |> ExRatatui.SSH.Daemon.ensure_host_key!()
  end

  defp wait_for(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end
  end
end

ImageDemo.Runner.main(System.argv())
