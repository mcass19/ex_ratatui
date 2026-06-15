defmodule ExRatatui.ThreeD.Mesh do
  @moduledoc """
  Geometry for a 3D object: a built-in primitive or a custom triangle mesh.

  Primitive meshes (`:cube`, `:sphere`, `:plane`) are built natively each frame
  and carry no geometry data. Custom meshes carry their own vertices and triangle
  indices; vertex normals are computed natively when omitted.

  ## Fields

    * `:kind` - `:cube`, `:sphere`, `:plane`, or `:custom`
    * `:stacks`, `:slices` - sphere tessellation (only for `:sphere`)
    * `:vertices` - list of `{x, y, z}` positions (only for `:custom`)
    * `:indices` - flat list of triangle indices, length a multiple of 3
      (only for `:custom`)
    * `:normals` - optional per-vertex `{x, y, z}` normals (only for `:custom`)
    * `:uvs` - optional per-vertex `{u, v}` texture coordinates (only for `:custom`)

  Prefer the constructors over building the struct by hand.

  ## Examples

      iex> ExRatatui.ThreeD.Mesh.cube().kind
      :cube

      iex> sphere = ExRatatui.ThreeD.Mesh.sphere()
      iex> {sphere.kind, sphere.stacks, sphere.slices}
      {:sphere, 16, 24}

      iex> sphere = ExRatatui.ThreeD.Mesh.sphere(8, 12)
      iex> {sphere.kind, sphere.stacks, sphere.slices}
      {:sphere, 8, 12}

      iex> ExRatatui.ThreeD.Mesh.plane().kind
      :plane

      iex> mesh = ExRatatui.ThreeD.Mesh.new([{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}], [0, 1, 2])
      iex> {mesh.kind, mesh.indices}
      {:custom, [0, 1, 2]}
  """

  @type vec3 :: {number(), number(), number()}
  @type kind :: :cube | :sphere | :plane | :custom

  @type t :: %__MODULE__{
          kind: kind(),
          stacks: pos_integer() | nil,
          slices: pos_integer() | nil,
          vertices: [vec3()] | nil,
          indices: [non_neg_integer()] | nil,
          normals: [vec3()] | nil,
          uvs: [{number(), number()}] | nil
        }

  defstruct kind: :cube,
            stacks: nil,
            slices: nil,
            vertices: nil,
            indices: nil,
            normals: nil,
            uvs: nil

  @doc "A unit cube centered at the origin."
  @spec cube() :: t()
  def cube, do: %__MODULE__{kind: :cube}

  @doc "A unit sphere tessellated into `stacks` rings and `slices` segments."
  @spec sphere(pos_integer(), pos_integer()) :: t()
  def sphere(stacks \\ 16, slices \\ 24)
      when is_integer(stacks) and stacks > 0 and is_integer(slices) and slices > 0 do
    %__MODULE__{kind: :sphere, stacks: stacks, slices: slices}
  end

  @doc "A unit plane in the XZ axis (normal +Y)."
  @spec plane() :: t()
  def plane, do: %__MODULE__{kind: :plane}

  @cylinder_segments 24

  @doc """
  A unit cylinder: radius 0.5, height 1.0, axis +Y, centered at the origin.

  `segments` is the number of radial subdivisions (minimum 3). Returns a custom
  mesh (`kind: :custom`) with caps and per-vertex normals.
  """
  @spec cylinder(pos_integer()) :: t()
  def cylinder(segments \\ @cylinder_segments) when is_integer(segments) and segments >= 3 do
    r = 0.5
    half = 0.5
    two_pi = 2.0 * :math.pi()
    angles = Enum.map(0..(segments - 1), fn i -> i / segments * two_pi end)

    side =
      Enum.flat_map(angles, fn a ->
        nx = :math.cos(a)
        nz = :math.sin(a)

        [
          {{r * nx, -half, r * nz}, {nx, 0.0, nz}},
          {{r * nx, half, r * nz}, {nx, 0.0, nz}}
        ]
      end)

    bottom_ring =
      Enum.map(angles, fn a -> {{r * :math.cos(a), -half, r * :math.sin(a)}, {0.0, -1.0, 0.0}} end)

    top_ring =
      Enum.map(angles, fn a -> {{r * :math.cos(a), half, r * :math.sin(a)}, {0.0, 1.0, 0.0}} end)

    verts =
      side ++
        bottom_ring ++
        top_ring ++ [{{0.0, -half, 0.0}, {0.0, -1.0, 0.0}}, {{0.0, half, 0.0}, {0.0, 1.0, 0.0}}]

    bottom_off = 2 * segments
    top_off = bottom_off + segments
    bottom_center = top_off + segments
    top_center = bottom_center + 1

    side_indices =
      Enum.flat_map(0..(segments - 1), fn i ->
        ni = rem(i + 1, segments)
        # CCW from outside: (b_i, b_ni, t_ni), (b_i, t_ni, t_i)
        [2 * i, 2 * ni, 2 * ni + 1, 2 * i, 2 * ni + 1, 2 * i + 1]
      end)

    bottom_indices =
      Enum.flat_map(0..(segments - 1), fn i ->
        ni = rem(i + 1, segments)
        [bottom_center, bottom_off + ni, bottom_off + i]
      end)

    top_indices =
      Enum.flat_map(0..(segments - 1), fn i ->
        ni = rem(i + 1, segments)
        [top_center, top_off + i, top_off + ni]
      end)

    new(
      Enum.map(verts, fn {p, _n} -> p end),
      side_indices ++ bottom_indices ++ top_indices,
      normals: Enum.map(verts, fn {_p, n} -> n end)
    )
  end

  @doc """
  A custom triangle mesh from `vertices` and a flat list of triangle `indices`.

  Options:

    * `:normals` - per-vertex normals; computed natively when omitted
    * `:uvs` - per-vertex texture coordinates
  """
  @spec new([vec3()], [non_neg_integer()], keyword()) :: t()
  def new(vertices, indices, opts \\ []) when is_list(vertices) and is_list(indices) do
    %__MODULE__{
      kind: :custom,
      vertices: vertices,
      indices: indices,
      normals: Keyword.get(opts, :normals),
      uvs: Keyword.get(opts, :uvs)
    }
  end
end
