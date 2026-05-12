# Example: a minimal slide deck driven by arrow keys.
#
# Three slides: title, image (from picsum.photos or IMAGE_PATH), and a
# code block. Demonstrates the "TUI slides with memes / photos" use case
# motivating the ratatui-image integration.
#
# Run with:    mix run examples/slides.exs
# Controls:    ←/h or →/l = prev/next   q = quit

alias ExRatatui.Event
alias ExRatatui.Image
alias ExRatatui.Layout
alias ExRatatui.Layout.Rect
alias ExRatatui.Style
alias ExRatatui.Widgets.{Block, Paragraph}

defmodule Slides do
  use ExRatatui.App

  alias ExRatatui.Image

  @impl true
  def mount(_opts) do
    {:ok, image} = Image.new(load_image_bytes(), protocol: :auto, resize: :fit)
    # `probe_image_protocol: true` runs `Picker::from_query_stdio` once
    # after mount on the :local transport — `:auto` images then resolve
    # to the detected protocol (Kitty in Kitty/Ghostty, halfblocks
    # elsewhere). Soft-fails silently if the probe can't complete.
    {:ok, %{slide: 0, image: image, total: 3}, probe_image_protocol: true}
  end

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [body_area, footer_area] =
      Layout.split(area, :vertical, [{:min, 0}, {:length, 3}])

    body = render_slide(state.slide, state.image)

    footer = %Paragraph{
      text: "  slide #{state.slide + 1}/#{state.total}   ←/→ navigate   q quit",
      style: %Style{fg: :dark_gray},
      block: %Block{borders: [:top], border_style: %Style{fg: :dark_gray}}
    }

    (body ++ [{footer, footer_area}])
    |> rebase(body_area, footer_area)
  end

  # Slide 0: title
  defp render_slide(0, _image) do
    [
      {%Paragraph{
         text: "\n\n  ExRatatui slides demo",
         style: %Style{fg: :light_cyan, modifiers: [:bold]},
         alignment: :center,
         block: %Block{borders: [:all], border_type: :rounded, title: " title "}
       }, :body}
    ]
  end

  # Slide 1: image
  defp render_slide(1, image) do
    [
      {%Block{borders: [:all], border_type: :rounded, title: " photo (picsum.photos) "}, :body},
      {image, :inner_body}
    ]
  end

  # Slide 2: code
  defp render_slide(2, _image) do
    [
      {%Paragraph{
         text: """


           {:ok, image} = ExRatatui.Image.new(File.read!("cover.png"))

           def view(_model, frame) do
             [{image, %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}]
           end
         """,
         style: %Style{fg: :light_green},
         block: %Block{borders: [:all], border_type: :rounded, title: " code "}
       }, :body}
    ]
  end

  # Map symbolic slot tags to concrete rects.
  defp rebase(commands, body_area, _footer_area) do
    inner = %Rect{
      x: body_area.x + 2,
      y: body_area.y + 1,
      width: max(body_area.width - 4, 1),
      height: max(body_area.height - 2, 1)
    }

    Enum.map(commands, fn
      {widget, :body} -> {widget, body_area}
      {widget, :inner_body} -> {widget, inner}
      pair -> pair
    end)
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: code, kind: "press"}, state)
      when code in ["right", "l", " "] do
    {:noreply, %{state | slide: rem(state.slide + 1, state.total)}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["left", "h"] do
    {:noreply, %{state | slide: rem(state.slide - 1 + state.total, state.total)}}
  end

  def handle_event(_event, state), do: {:noreply, state}

  # -- image fetch helpers ---------------------------------------------

  defp load_image_bytes do
    case System.get_env("IMAGE_PATH") do
      nil -> fetch_picsum_or_fallback()
      path -> File.read!(path)
    end
  end

  defp fetch_picsum_or_fallback do
    case fetch("https://picsum.photos/600/400") do
      {:ok, bytes} -> bytes
      _ -> fallback_png()
    end
  end

  defp fetch(url) do
    :inets.start()
    :ssl.start()

    case :httpc.request(
           :get,
           {String.to_charlist(url), []},
           [{:timeout, 5_000}],
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, _, body}} when status in 200..299 -> {:ok, body}
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

{:ok, pid} = Slides.start_link([])
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
end
