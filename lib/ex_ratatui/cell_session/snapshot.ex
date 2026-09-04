defmodule ExRatatui.CellSession.Snapshot do
  @moduledoc """
  Full-buffer snapshot returned by `ExRatatui.CellSession.take_cells/1`.

  Carries the dimensions of the buffer plus every cell, in row-major
  order — `cells` has length `width * height`. Use this when the
  complete picture is needed: initial paint after a fresh client
  connects, one-off screenshot, regression test fixture.

  For streaming updates use `ExRatatui.CellSession.take_cells_diff/1`
  instead, which returns the same `Cell` shape inside an
  `ExRatatui.CellSession.Diff` payload but only includes cells that
  changed since the last diff call.

  ## Fields

    * `:width` — terminal width in cells
    * `:height` — terminal height in cells
    * `:cells` — list of `t:ExRatatui.CellSession.Cell.t/0` in
      row-major order: `(0,0), (1,0), ..., (W-1,0), (0,1), ...`

  ## Examples

      iex> %ExRatatui.CellSession.Snapshot{}
      %ExRatatui.CellSession.Snapshot{width: 0, height: 0, cells: []}
  """

  alias ExRatatui.CellSession.{Cell, Region}

  defstruct width: 0, height: 0, cells: [], regions: []

  @type t :: %__MODULE__{
          width: non_neg_integer(),
          height: non_neg_integer(),
          cells: [Cell.t()],
          regions: [Region.t()]
        }

  @doc """
  Builds a `t:t/0` from the raw `%{width, height, cells, regions}` map the
  NIF returns. Each tuple in `cells` is converted via
  `ExRatatui.CellSession.Cell.from_tuple/1`, each map in `regions` via
  `ExRatatui.CellSession.Region.from_native/1`. `regions` is the complete
  list of pixel regions on screen (always empty for a session created
  without a `:font_size`).
  """
  @spec from_native(%{
          required(:width) => non_neg_integer(),
          required(:height) => non_neg_integer(),
          required(:cells) => [tuple()],
          optional(:regions) => [map()]
        }) :: t()
  def from_native(%{width: width, height: height, cells: cells} = native) do
    %__MODULE__{
      width: width,
      height: height,
      cells: Enum.map(cells, &Cell.from_tuple/1),
      regions: native |> Map.get(:regions, []) |> Enum.map(&Region.from_native/1)
    }
  end
end
