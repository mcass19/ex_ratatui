defmodule ExRatatui.Layout.Padding do
  @moduledoc """
  Constructors for `%ExRatatui.Widgets.Block{}` padding tuples.

  `Block`'s `:padding` field is a `{left, right, top, bottom}` tuple of
  non-negative integers. Writing those out by hand is noisy for the
  common symmetric cases — these helpers mirror ratatui's `Padding`
  constructors and return the tuple `Block` already accepts, so they
  drop straight into `padding:`.

      %Block{padding: ExRatatui.Layout.Padding.uniform(1)}
      %Block{padding: ExRatatui.Layout.Padding.symmetric(2, 1)}

  Every helper returns a plain `{l, r, t, b}` tuple — there is no
  struct and no runtime cost beyond building the tuple.
  """

  @type t :: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}

  @doc """
  The same padding on all four sides.

  ## Examples

      iex> ExRatatui.Layout.Padding.uniform(2)
      {2, 2, 2, 2}
  """
  @spec uniform(non_neg_integer()) :: t()
  def uniform(n) when is_integer(n) and n >= 0, do: {n, n, n, n}

  @doc """
  Horizontal padding on left + right, vertical padding on top + bottom.

  ## Examples

      iex> ExRatatui.Layout.Padding.symmetric(3, 1)
      {3, 3, 1, 1}
  """
  @spec symmetric(non_neg_integer(), non_neg_integer()) :: t()
  def symmetric(horizontal, vertical)
      when is_integer(horizontal) and horizontal >= 0 and is_integer(vertical) and vertical >= 0,
      do: {horizontal, horizontal, vertical, vertical}

  @doc """
  Padding on left + right only; top + bottom are zero.

  ## Examples

      iex> ExRatatui.Layout.Padding.horizontal(2)
      {2, 2, 0, 0}
  """
  @spec horizontal(non_neg_integer()) :: t()
  def horizontal(n) when is_integer(n) and n >= 0, do: {n, n, 0, 0}

  @doc """
  Padding on top + bottom only; left + right are zero.

  ## Examples

      iex> ExRatatui.Layout.Padding.vertical(1)
      {0, 0, 1, 1}
  """
  @spec vertical(non_neg_integer()) :: t()
  def vertical(n) when is_integer(n) and n >= 0, do: {0, 0, n, n}

  @doc """
  Explicit per-side padding. The identity constructor — included so a
  call site can stay in the `Padding.*` namespace for all four cases.

  ## Examples

      iex> ExRatatui.Layout.Padding.new(1, 2, 3, 4)
      {1, 2, 3, 4}
  """
  @spec new(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: t()
  def new(left, right, top, bottom)
      when is_integer(left) and left >= 0 and is_integer(right) and right >= 0 and
             is_integer(top) and top >= 0 and is_integer(bottom) and bottom >= 0,
      do: {left, right, top, bottom}
end
