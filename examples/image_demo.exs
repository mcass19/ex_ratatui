# Example: interactive image rendering demo.
#
# Run with: mix run examples/image_demo.exs
#
# Controls:
#   p — cycle protocol (auto / halfblocks / kitty / sixel / iterm2)
#   r — cycle resize  (fit / crop / scale)
#   q — quit
#
# Image source:
#   - IMAGE_PATH env var, if set, points to a local image file
#   - otherwise picsum.photos/400/300 is fetched once at startup
#   - if that fails too, falls back to a 1x1 magenta PNG (so the demo
#     still runs offline; just not very visually interesting)
#
# Best viewed in a Kitty/Ghostty/WezTerm terminal. NOTE: this demo runs
# under `ExRatatui.App` which doesn't expose the terminal_ref to
# `mount/1`, so it can't call `ExRatatui.Image.auto_local_protocol/1`
# to enable native protocol detection — the demo therefore renders
# with the (8, 16) default font size. For a real Kitty-detecting demo,
# call `auto_local_protocol/1` from a script that uses `ExRatatui.run/1`
# directly (see `counter.exs` for that entry-point pattern).
#
# Initial settings: protocol `:auto` (resolves to halfblocks without
# the probe wired in) and resize `:scale` so the photo fills the
# available area immediately. Press `r` to cycle to `:fit` if you
# want to see aspect-preserving anchoring behavior.

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

    {:ok,
     %{
       image: image,
       image_bytes: bytes,
       protocol: :auto,
       resize: :scale,
       image_size: {w, h},
       probe: probe_string()
     }}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [image_area, status_area, help_area] =
      Layout.split(area, :vertical, [{:min, 0}, {:length, 3}, {:length, 3}])

    {iw, ih} = state.image_size
    {fw, fh} = state.probe

    status = %Paragraph{
      text:
        "  protocol: #{inspect(state.protocol)}   resize: #{inspect(state.resize)}   image: #{iw}x#{ih}   tty: #{fw}x#{fh}",
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

{:ok, pid} = ImageDemo.start_link([])
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
