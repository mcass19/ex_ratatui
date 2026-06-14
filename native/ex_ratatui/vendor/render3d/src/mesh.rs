use crate::math::Vec3;

/// A single vertex with position, normal, and texture coordinates.
#[derive(Debug, Clone, Copy)]
pub struct Vertex {
    pub position: Vec3,
    pub normal: Vec3,
    pub uv: [f32; 2],
}

impl Vertex {
    pub fn new(position: Vec3, normal: Vec3) -> Self {
        Self {
            position,
            normal,
            uv: [0.0, 0.0],
        }
    }

    pub fn with_uv(mut self, u: f32, v: f32) -> Self {
        self.uv = [u, v];
        self
    }
}

/// An indexed triangle mesh.
#[derive(Debug, Clone)]
pub struct Mesh {
    pub vertices: Vec<Vertex>,
    /// Triangle indices (length must be a multiple of 3).
    pub indices: Vec<u32>,
}

impl Mesh {
    pub fn new(vertices: Vec<Vertex>, indices: Vec<u32>) -> Self {
        debug_assert!(indices.len().is_multiple_of(3), "indices length must be a multiple of 3");
        Self { vertices, indices }
    }

    pub fn triangle_count(&self) -> usize {
        self.indices.len() / 3
    }
}

/// Compute smooth vertex normals by averaging face normals.
///
/// Vertices must already have positions set. Their normals will be overwritten.
pub fn compute_normals(vertices: &mut [Vertex], indices: &[u32]) {
    for tri in indices.chunks_exact(3) {
        let (i0, i1, i2) = (tri[0] as usize, tri[1] as usize, tri[2] as usize);
        let v0 = vertices[i0].position;
        let v1 = vertices[i1].position;
        let v2 = vertices[i2].position;
        let face_normal = (v1 - v0).cross(v2 - v0);
        vertices[i0].normal += face_normal;
        vertices[i1].normal += face_normal;
        vertices[i2].normal += face_normal;
    }
    for v in vertices.iter_mut() {
        v.normal = v.normal.normalize_or_zero();
    }
}
