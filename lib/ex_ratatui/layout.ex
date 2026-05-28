defmodule ExRatatui.Layout do
  @moduledoc """
  Layout system for splitting areas into sub-regions.

  Uses ratatui's constraint-based layout engine to divide a `Rect` into
  multiple sub-regions along a direction.

  ## Constraints

    * `{:percentage, n}` - percentage of the total space
    * `{:length, n}` - exact number of cells
    * `{:min, n}` - minimum number of cells
    * `{:max, n}` - maximum number of cells
    * `{:ratio, numerator, denominator}` - fractional ratio
    * `{:fill, weight}` - proportional share of the remaining space
      after higher-priority constraints (Length/Percentage/Ratio/etc.)
      are satisfied. `{:fill, 1}` + `{:fill, 2}` splits leftover space
      in a 1:2 ratio. Useful for "growable" panels in dashboards.

  ## Options

  `split/4` accepts a fourth keyword-list argument:

    * `:flex` — how excess space is distributed when constraints don't
      fill the area. One of:
      * `:legacy` — pre-Flex behaviour; last constraint absorbs excess
      * `:start` — pack from the start
      * `:end` — pack from the end
      * `:center` — pack centered, excess split between both ends
      * `:space_between` — distribute excess between segments
      * `:space_around` — distribute excess around every segment
      Defaults to ratatui's `Flex::default()` (currently `:start`).
    * `:spacing` — non-negative integer cells inserted between every
      pair of adjacent segments. Defaults to `0`.
    * `:margin` — non-negative integer cells inset on all four sides of
      the area before it is split. Defaults to `0`.
    * `:horizontal_margin` / `:vertical_margin` — per-axis inset that
      overrides `:margin` for that axis when given. Use these for
      asymmetric insets (e.g. `horizontal_margin: 2, vertical_margin: 1`).

  ## Examples

      area = %Rect{x: 0, y: 0, width: 80, height: 24}

      # Split the area but leave a 1-cell border around the edges.
      [body] = Layout.split(area, :vertical, [{:min, 0}], margin: 1)

      area = %Rect{x: 0, y: 0, width: 80, height: 24}

      [header, body, footer] = Layout.split(area, :vertical, [
        {:length, 3},
        {:min, 0},
        {:length, 1}
      ])

      [sidebar, main] = Layout.split(body, :horizontal, [
        {:percentage, 30},
        {:percentage, 70}
      ])

      # Centered popup with 40-cell fixed width
      [popup] = Layout.split(area, :horizontal, [{:length, 40}], flex: :center)

      # Two equal-weight growable panels with a 2-cell gutter
      [left, right] = Layout.split(area, :horizontal, [{:fill, 1}, {:fill, 1}],
        spacing: 2)
  """

  alias ExRatatui.Layout.Rect

  @type direction :: :horizontal | :vertical
  @type constraint ::
          {:percentage, non_neg_integer()}
          | {:length, non_neg_integer()}
          | {:min, non_neg_integer()}
          | {:max, non_neg_integer()}
          | {:ratio, non_neg_integer(), non_neg_integer()}
          | {:fill, non_neg_integer()}

  @type flex ::
          :legacy | :start | :end | :center | :space_between | :space_around

  @type split_opt ::
          {:flex, flex()}
          | {:spacing, non_neg_integer()}
          | {:margin, non_neg_integer()}
          | {:horizontal_margin, non_neg_integer()}
          | {:vertical_margin, non_neg_integer()}

  @doc """
  Splits a `Rect` into sub-regions based on direction and constraints.

  Accepts an optional 4th argument with `:flex` and `:spacing` options
  (see module doc). Returns a list of `%Rect{}` structs or
  `{:error, reason}` on failure.

  ## Examples

      iex> alias ExRatatui.Layout
      iex> alias ExRatatui.Layout.Rect
      iex> area = %Rect{x: 0, y: 0, width: 80, height: 24}
      iex> [top, bottom] = Layout.split(area, :vertical, [{:percentage, 50}, {:percentage, 50}])
      iex> top
      %Rect{x: 0, y: 0, width: 80, height: 12}
      iex> bottom
      %Rect{x: 0, y: 12, width: 80, height: 12}

      iex> alias ExRatatui.Layout
      iex> alias ExRatatui.Layout.Rect
      iex> area = %Rect{x: 0, y: 0, width: 100, height: 1}
      iex> [left, right] = Layout.split(area, :horizontal, [{:length, 20}, {:min, 0}])
      iex> left
      %Rect{x: 0, y: 0, width: 20, height: 1}
      iex> right
      %Rect{x: 20, y: 0, width: 80, height: 1}

      iex> alias ExRatatui.Layout
      iex> alias ExRatatui.Layout.Rect
      iex> area = %Rect{x: 0, y: 0, width: 30, height: 1}
      iex> [popup] = Layout.split(area, :horizontal, [{:length, 10}], flex: :center)
      iex> popup
      %Rect{x: 10, y: 0, width: 10, height: 1}

      iex> alias ExRatatui.Layout
      iex> alias ExRatatui.Layout.Rect
      iex> area = %Rect{x: 0, y: 0, width: 22, height: 1}
      iex> [left, right] = Layout.split(area, :horizontal, [{:length, 10}, {:length, 10}], spacing: 2)
      iex> left.width == 10 and right.x == 12 and right.width == 10
      true
  """
  @spec split(Rect.t(), direction(), [constraint()], [split_opt()]) ::
          [Rect.t()] | {:error, term()}
  def split(area, direction, constraints, opts \\ [])

  def split(%Rect{} = area, direction, constraints, opts)
      when direction in [:horizontal, :vertical] and is_list(constraints) and is_list(opts) do
    rect_map = %{"x" => area.x, "y" => area.y, "width" => area.width, "height" => area.height}

    case ExRatatui.Native.layout_split(
           rect_map,
           Atom.to_string(direction),
           Enum.map(constraints, &encode_constraint/1),
           encode_opts(opts)
         ) do
      rects when is_list(rects) ->
        Enum.map(rects, fn {x, y, width, height} ->
          %Rect{x: x, y: y, width: width, height: height}
        end)

      {:error, _} = err ->
        err
    end
  end

  @doc false
  def encode_constraint({:percentage, n}), do: %{"type" => "percentage", "value" => n}
  def encode_constraint({:length, n}), do: %{"type" => "length", "value" => n}
  def encode_constraint({:min, n}), do: %{"type" => "min", "value" => n}
  def encode_constraint({:max, n}), do: %{"type" => "max", "value" => n}
  def encode_constraint({:ratio, num, den}), do: %{"type" => "ratio", "num" => num, "den" => den}
  def encode_constraint({:fill, n}), do: %{"type" => "fill", "value" => n}

  defp encode_opts(opts) do
    %{}
    |> maybe_put_flex(Keyword.get(opts, :flex))
    |> maybe_put_spacing(Keyword.get(opts, :spacing))
    |> maybe_put_margin("margin", Keyword.get(opts, :margin))
    |> maybe_put_margin("horizontal_margin", Keyword.get(opts, :horizontal_margin))
    |> maybe_put_margin("vertical_margin", Keyword.get(opts, :vertical_margin))
  end

  defp maybe_put_flex(map, nil), do: map

  defp maybe_put_flex(map, flex)
       when flex in [:legacy, :start, :end, :center, :space_between, :space_around] do
    Map.put(map, "flex", Atom.to_string(flex))
  end

  defp maybe_put_flex(_map, other) do
    raise ArgumentError,
          "Layout.split :flex expected one of :legacy, :start, :end, :center, :space_between, :space_around, got: #{inspect(other)}"
  end

  defp maybe_put_spacing(map, nil), do: map

  defp maybe_put_spacing(map, n) when is_integer(n) and n >= 0,
    do: Map.put(map, "spacing", n)

  defp maybe_put_spacing(_map, other) do
    raise ArgumentError,
          "Layout.split :spacing expected a non-negative integer, got: #{inspect(other)}"
  end

  defp maybe_put_margin(map, _key, nil), do: map

  defp maybe_put_margin(map, key, n) when is_integer(n) and n >= 0,
    do: Map.put(map, key, n)

  defp maybe_put_margin(_map, key, other) do
    raise ArgumentError,
          "Layout.split :#{key} expected a non-negative integer, got: #{inspect(other)}"
  end
end
