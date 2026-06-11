defmodule ExRatatui.Focus do
  @moduledoc """
  Focus management for multi-panel apps.

  `Focus` is a tiny state machine over an ordered ring of focusable
  IDs. You declare the IDs up front, feed every key event through
  `handle_key/2`, and pattern-match on `current/1` to decide which
  widget receives the keystroke. `handle_key/2` consumes
  Tab / Shift+Tab (or your overrides) and passes everything else
  through unchanged.

  There is no process, no macro, no protocol — just a struct you keep
  in your reducer state or `ExRatatui.App` model.

  ## Caller pattern

      def handle_event(%Event.Key{} = key, state) do
        {focus, key} = Focus.handle_key(state.focus, key)
        state = %{state | focus: focus}

        case key do
          nil ->
            # consumed by Focus (Tab / Shift+Tab); nothing more to do
            {:noreply, state}

          key ->
            case Focus.current(focus) do
              :search  -> {:noreply, update_search(state, key)}
              :results -> {:noreply, update_results(state, key)}
              :details -> {:noreply, update_details(state, key)}
            end
        end
      end

  ## Styling the focused widget

  `Focus` never touches widget structs. Use `focused?/2` to decide the
  style yourself:

      border_style =
        if Focus.focused?(focus, :search),
          do: %Style{fg: :yellow},
          else: %Style{fg: :gray}

      %TextInput{
        state: search_state,
        block: %Block{borders: :all, border_style: border_style}
      }

  ## Custom keys

  Pass `:next_keys` / `:prev_keys` to `new/2` as lists of
  `%ExRatatui.Event.Key{}` structs. Only `:code` and `:modifiers`
  matter — `:kind` is ignored, and `:modifiers` is compared as a set
  (order-independent).

      Focus.new([:a, :b, :c],
        next_keys: [%Event.Key{code: "tab"}, %Event.Key{code: "right", modifiers: ["ctrl"]}],
        prev_keys: [%Event.Key{code: "left", modifiers: ["ctrl"]}]
      )

  ## Mouse routing

  Associate each focusable ID with a hit-test `%ExRatatui.Layout.Rect{}`
  after computing layout (typically inside a `%Event.Resize{}` handler
  or any state change that affects geometry). `handle_mouse/2` then
  focuses the widget under a left-click, passing the event through so
  the underlying widget can also react.

      def handle_event(%Event.Resize{width: w, height: h}, state) do
        [search_rect, body_rect] =
          Layout.split(%Rect{x: 0, y: 0, width: w, height: h}, :vertical,
            [{:length, 3}, {:min, 0}])

        focus =
          state.focus
          |> Focus.set_region(:search, search_rect)
          |> Focus.set_region(:body, body_rect)

        %{state | focus: focus}
      end

      def handle_event(%Event.Mouse{} = mouse, state) do
        {focus, mouse} = Focus.handle_mouse(state.focus, mouse)
        # mouse is always returned for downstream handling — left-click
        # focuses the region's ID; scroll/drag/right-click are pass-through.
        ...
      end

  Scroll-wheel routing is intentionally not built in: the conventional
  contract is "scroll goes to the focused widget", which the app can
  implement by inspecting `Focus.current/1` after `handle_mouse/2`
  returns. Apps that prefer "scroll goes to the widget under the
  cursor" can call `Focus.at/3` directly.
  """

  alias ExRatatui.Event
  alias ExRatatui.Layout.Rect

  @enforce_keys [:ids, :index, :next_keys, :prev_keys]
  defstruct [:ids, :index, :next_keys, :prev_keys, regions: %{}]

  @type id :: atom()
  @type t :: %__MODULE__{
          ids: [id(), ...],
          index: non_neg_integer(),
          next_keys: [Event.Key.t()],
          prev_keys: [Event.Key.t()],
          regions: %{id() => Rect.t()}
        }

  @default_next_keys [%Event.Key{code: "tab"}]
  @default_prev_keys [
    %Event.Key{code: "back_tab"},
    %Event.Key{code: "tab", modifiers: ["shift"]}
  ]

  @doc """
  Builds a focus ring from an ordered list of IDs.

  ## Options

    * `:initial` — ID to start focused on (defaults to the first entry).
    * `:next_keys` — list of `%ExRatatui.Event.Key{}` that advance focus
      (defaults to Tab).
    * `:prev_keys` — list of `%ExRatatui.Event.Key{}` that retreat focus
      (defaults to Shift+Tab and `back_tab`).

  Raises `ArgumentError` for an empty list, duplicate IDs, non-atom
  entries, or an `:initial` that is not in `ids`.
  """
  @spec new([id(), ...], keyword()) :: t()
  def new(ids, opts \\ []) when is_list(ids) do
    validate_ids!(ids)

    initial = Keyword.get(opts, :initial, hd(ids))
    index = index_of!(ids, initial)

    %__MODULE__{
      ids: ids,
      index: index,
      next_keys: Keyword.get(opts, :next_keys, @default_next_keys),
      prev_keys: Keyword.get(opts, :prev_keys, @default_prev_keys)
    }
  end

  @doc """
  Returns the currently focused ID.

  ## Examples

      iex> ExRatatui.Focus.new([:a, :b, :c]) |> ExRatatui.Focus.current()
      :a

      iex> ExRatatui.Focus.new([:a, :b, :c], initial: :b) |> ExRatatui.Focus.current()
      :b
  """
  @spec current(t()) :: id()
  def current(%__MODULE__{ids: ids, index: index}), do: Enum.at(ids, index)

  @doc """
  Returns `true` when `id` is the currently focused ID.

  ## Examples

      iex> focus = ExRatatui.Focus.new([:a, :b, :c])
      iex> ExRatatui.Focus.focused?(focus, :a)
      true
      iex> ExRatatui.Focus.focused?(focus, :b)
      false
  """
  @spec focused?(t(), id()) :: boolean()
  def focused?(%__MODULE__{} = focus, id), do: current(focus) == id

  @doc """
  Jumps focus to a specific ID.

  Raises `ArgumentError` if `id` is not in the ring.
  """
  @spec focus(t(), id()) :: t()
  def focus(%__MODULE__{ids: ids} = focus, id) do
    %{focus | index: index_of!(ids, id)}
  end

  @doc """
  Advances focus to the next ID, wrapping from the last back to the first.
  """
  @spec next(t()) :: t()
  def next(%__MODULE__{ids: ids, index: index} = focus) do
    %{focus | index: rem(index + 1, length(ids))}
  end

  @doc """
  Retreats focus to the previous ID, wrapping from the first back to the last.
  """
  @spec prev(t()) :: t()
  def prev(%__MODULE__{ids: ids, index: index} = focus) do
    %{focus | index: rem(index - 1 + length(ids), length(ids))}
  end

  @doc """
  Routes a key event through the focus ring.

  Returns `{focus, nil}` when the event matched a `:next_keys` or
  `:prev_keys` entry (focus moved, event consumed). Returns
  `{focus, event}` unchanged otherwise so the caller can forward it to
  the currently focused widget.

  Matching compares `:code` and `:modifiers` (as a set). `:kind` is
  ignored.
  """
  @spec handle_key(t(), Event.Key.t()) :: {t(), Event.Key.t() | nil}
  def handle_key(%__MODULE__{} = focus, %Event.Key{} = event) do
    cond do
      matches?(event, focus.next_keys) -> {next(focus), nil}
      matches?(event, focus.prev_keys) -> {prev(focus), nil}
      true -> {focus, event}
    end
  end

  @doc """
  Associates a hit-test region with a focusable ID.

  Apps call this after computing layout (typically inside a `%Event.Resize{}`
  handler, or any state change that affects the on-screen geometry of the
  focusable widgets). `handle_mouse/2` uses the registered regions to focus
  the widget under a click.

  Raises `ArgumentError` if `id` is not in the ring.

  ## Examples

      iex> focus = ExRatatui.Focus.new([:search, :results])
      iex> rect = %ExRatatui.Layout.Rect{x: 0, y: 0, width: 40, height: 3}
      iex> focus |> ExRatatui.Focus.set_region(:search, rect) |> ExRatatui.Focus.region(:search)
      %ExRatatui.Layout.Rect{x: 0, y: 0, width: 40, height: 3}
  """
  @spec set_region(t(), id(), Rect.t()) :: t()
  def set_region(%__MODULE__{ids: ids, regions: regions} = focus, id, %Rect{} = rect) do
    _ = index_of!(ids, id)
    %{focus | regions: Map.put(regions, id, rect)}
  end

  @doc """
  Batch-registers multiple regions in one call.

  Equivalent to calling `set_region/3` for each entry. Raises if any ID
  is missing from the ring.

  ## Examples

      iex> focus = ExRatatui.Focus.new([:a, :b])
      iex> rects = %{
      ...>   a: %ExRatatui.Layout.Rect{x: 0, y: 0, width: 10, height: 1},
      ...>   b: %ExRatatui.Layout.Rect{x: 0, y: 1, width: 10, height: 1}
      ...> }
      iex> focus |> ExRatatui.Focus.set_regions(rects) |> ExRatatui.Focus.region(:b)
      %ExRatatui.Layout.Rect{x: 0, y: 1, width: 10, height: 1}
  """
  @spec set_regions(t(), %{id() => Rect.t()}) :: t()
  def set_regions(%__MODULE__{} = focus, regions) when is_map(regions) do
    Enum.reduce(regions, focus, fn {id, rect}, acc -> set_region(acc, id, rect) end)
  end

  @doc """
  Returns the region registered for `id`, or `nil` if none is registered.
  """
  @spec region(t(), id()) :: Rect.t() | nil
  def region(%__MODULE__{regions: regions}, id), do: Map.get(regions, id)

  @doc """
  Returns the focusable ID whose region contains the point `(x, y)`, or
  `nil` if no registered region contains the point.

  When regions overlap, the smallest one (by area) wins — overlap usually
  means a focusable widget sits inside a larger focusable container, and
  the leaf should claim the click.

  ## Examples

      iex> alias ExRatatui.{Focus, Layout.Rect}
      iex> focus =
      ...>   Focus.new([:a, :b])
      ...>   |> Focus.set_region(:a, %Rect{x: 0, y: 0, width: 10, height: 10})
      ...>   |> Focus.set_region(:b, %Rect{x: 2, y: 2, width: 2, height: 2})
      iex> Focus.at(focus, 3, 3)
      :b
      iex> Focus.at(focus, 8, 8)
      :a
      iex> Focus.at(focus, 50, 50)
      nil
  """
  @spec at(t(), non_neg_integer(), non_neg_integer()) :: id() | nil
  def at(%__MODULE__{regions: regions}, x, y)
      when is_integer(x) and is_integer(y) and x >= 0 and y >= 0 do
    regions
    |> Enum.filter(fn {_id, rect} -> contains?(rect, x, y) end)
    |> Enum.min_by(fn {_id, rect} -> rect.width * rect.height end, fn -> nil end)
    |> case do
      nil -> nil
      {id, _rect} -> id
    end
  end

  @doc """
  Routes a mouse event through the focus ring.

  On a left-button **down** event inside a registered region, focus
  moves to that region's ID and the event is **passed through** so the
  underlying widget can also react (toggle a checkbox, place a cursor,
  start a drag). Every other mouse event — clicks outside any
  registered region, right/middle clicks, scroll, drag, move, up — is
  returned unchanged with focus untouched.

  Returns `{focus, event}` regardless. Mirrors `handle_key/2` shape so
  the same caller pattern (`{focus, event} = Focus.handle_*(focus, event)`)
  works for both event types.

  ## Examples

      iex> alias ExRatatui.{Focus, Event, Layout.Rect}
      iex> focus =
      ...>   Focus.new([:a, :b])
      ...>   |> Focus.set_region(:a, %Rect{x: 0, y: 0, width: 10, height: 3})
      ...>   |> Focus.set_region(:b, %Rect{x: 0, y: 3, width: 10, height: 3})
      iex> click = %Event.Mouse{kind: "down", button: "left", x: 5, y: 4}
      iex> {focus, _event} = Focus.handle_mouse(focus, click)
      iex> Focus.current(focus)
      :b
  """
  @spec handle_mouse(t(), Event.Mouse.t()) :: {t(), Event.Mouse.t()}
  def handle_mouse(
        %__MODULE__{} = focus,
        %Event.Mouse{kind: "down", button: "left", x: x, y: y} = event
      ) do
    case at(focus, x, y) do
      nil -> {focus, event}
      id -> {focus(focus, id), event}
    end
  end

  def handle_mouse(%__MODULE__{} = focus, %Event.Mouse{} = event), do: {focus, event}

  defp contains?(%Rect{x: rx, y: ry, width: w, height: h}, x, y) do
    x >= rx and x < rx + w and y >= ry and y < ry + h
  end

  defp matches?(%Event.Key{code: code, modifiers: mods}, entries) do
    event_mods = MapSet.new(mods)

    Enum.any?(entries, fn %Event.Key{code: c, modifiers: m} ->
      c == code and MapSet.new(m) == event_mods
    end)
  end

  defp validate_ids!([]) do
    raise ArgumentError, "ExRatatui.Focus.new/2 requires a non-empty list of IDs"
  end

  defp validate_ids!(ids) do
    Enum.each(ids, fn id ->
      unless is_atom(id) do
        raise ArgumentError,
              "ExRatatui.Focus.new/2 IDs must be atoms, got: #{inspect(id)}"
      end
    end)

    if length(Enum.uniq(ids)) != length(ids) do
      raise ArgumentError,
            "ExRatatui.Focus.new/2 IDs must be unique, got: #{inspect(ids)}"
    end
  end

  defp index_of!(ids, id) do
    case Enum.find_index(ids, &(&1 == id)) do
      nil ->
        raise ArgumentError,
              "ID #{inspect(id)} not found in focus ring #{inspect(ids)}"

      index ->
        index
    end
  end
end
