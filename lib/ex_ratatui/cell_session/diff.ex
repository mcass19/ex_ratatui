defmodule ExRatatui.CellSession.Diff do
  @moduledoc """
  Delta payload returned by `ExRatatui.CellSession.take_cells_diff/1`.

  Carries the buffer's current dimensions plus only the cells that
  differ from the previously-surfaced state. Each op is a
  `t:ExRatatui.CellSession.Cell.t/0` — same shape as a snapshot cell,
  same `:row`/`:col` coordinates — just a smaller subset.

  ## When the full grid arrives in `:ops`

  Three cases produce a "full" payload (every cell as an op):

    * the very first call to `take_cells_diff/1` after constructing
      the session — there's no baseline to diff against
    * a `resize/3` happened between calls — the prior baseline is no
      longer a valid comparison reference
    * the session was closed and reopened (the baseline was wiped on
      `close/1`)

  Consumers can detect these cases by `length(diff.ops) == diff.width * diff.height`,
  or just paint every op uniformly — the result is the same.

  ## Why ops are cells, not a tagged op type

  There is only one operation: "set this position to this content."
  Clearing a cell is just setting it to a default-styled space.
  Tagging each op as `{:set, ...}` would be speculative future-proofing
  for an extension that may never come; if a richer op vocabulary
  becomes useful later, we'll introduce it as a heterogeneous list of
  tagged tuples without breaking existing consumers (just check the
  shape).

  ## Fields

    * `:width` — terminal width in cells (full, not the diff bounding box)
    * `:height` — terminal height in cells
    * `:ops` — list of `t:ExRatatui.CellSession.Cell.t/0` for cells
      that changed. Empty list means the buffer is identical to the
      prior snapshot.

  ## Examples

      iex> %ExRatatui.CellSession.Diff{}
      %ExRatatui.CellSession.Diff{width: 0, height: 0, ops: []}
  """

  alias ExRatatui.CellSession.Cell

  defstruct width: 0, height: 0, ops: []

  @type t :: %__MODULE__{
          width: non_neg_integer(),
          height: non_neg_integer(),
          ops: [Cell.t()]
        }

  @doc """
  Builds a `t:t/0` from the raw `%{width, height, ops}` map the NIF
  returns. Each tuple in `ops` is converted via
  `ExRatatui.CellSession.Cell.from_tuple/1`.
  """
  @spec from_native(%{
          required(:width) => non_neg_integer(),
          required(:height) => non_neg_integer(),
          required(:ops) => [tuple()]
        }) :: t()
  def from_native(%{width: width, height: height, ops: ops}) do
    %__MODULE__{
      width: width,
      height: height,
      ops: Enum.map(ops, &Cell.from_tuple/1)
    }
  end
end
