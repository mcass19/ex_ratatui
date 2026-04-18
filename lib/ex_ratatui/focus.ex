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
            state

          key ->
            case Focus.current(focus) do
              :search  -> update_search(state, key)
              :results -> update_results(state, key)
              :details -> update_details(state, key)
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
  """

  alias ExRatatui.Event

  @enforce_keys [:ids, :index, :next_keys, :prev_keys]
  defstruct [:ids, :index, :next_keys, :prev_keys]

  @type id :: atom()
  @type t :: %__MODULE__{
          ids: [id(), ...],
          index: non_neg_integer(),
          next_keys: [Event.Key.t()],
          prev_keys: [Event.Key.t()]
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
