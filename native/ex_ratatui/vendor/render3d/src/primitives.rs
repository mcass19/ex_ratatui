use crate::math::Vec3;
use crate::mesh::{Mesh, Vertex};

/// Create a unit cube centered at the origin (side length 1).
pub fn cube() -> Mesh {
    // 6 faces, 4 vertices each (separate normals per face), 2 triangles per face
    let mut vertices = Vec::with_capacity(24);
    let mut indices = Vec::with_capacity(36);

    let faces: [(Vec3, Vec3, Vec3, Vec3, Vec3); 6] = [
        // (normal, v0, v1, v2, v3) — CCW winding when viewed from outside
        // Front (+Z)
        (
            Vec3::Z,
            Vec3::new(-0.5, -0.5, 0.5),
            Vec3::new(0.5, -0.5, 0.5),
            Vec3::new(0.5, 0.5, 0.5),
            Vec3::new(-0.5, 0.5, 0.5),
        ),
        // Back (-Z)
        (
            Vec3::NEG_Z,
            Vec3::new(0.5, -0.5, -0.5),
            Vec3::new(-0.5, -0.5, -0.5),
            Vec3::new(-0.5, 0.5, -0.5),
            Vec3::new(0.5, 0.5, -0.5),
        ),
        // Right (+X)
        (
            Vec3::X,
            Vec3::new(0.5, -0.5, 0.5),
            Vec3::new(0.5, -0.5, -0.5),
            Vec3::new(0.5, 0.5, -0.5),
            Vec3::new(0.5, 0.5, 0.5),
        ),
        // Left (-X)
        (
            Vec3::NEG_X,
            Vec3::new(-0.5, -0.5, -0.5),
            Vec3::new(-0.5, -0.5, 0.5),
            Vec3::new(-0.5, 0.5, 0.5),
            Vec3::new(-0.5, 0.5, -0.5),
        ),
        // Top (+Y)
        (
            Vec3::Y,
            Vec3::new(-0.5, 0.5, 0.5),
            Vec3::new(0.5, 0.5, 0.5),
            Vec3::new(0.5, 0.5, -0.5),
            Vec3::new(-0.5, 0.5, -0.5),
        ),
        // Bottom (-Y)
        (
            Vec3::NEG_Y,
            Vec3::new(-0.5, -0.5, -0.5),
            Vec3::new(0.5, -0.5, -0.5),
            Vec3::new(0.5, -0.5, 0.5),
            Vec3::new(-0.5, -0.5, 0.5),
        ),
    ];

    for (normal, v0, v1, v2, v3) in &faces {
        let base = vertices.len() as u32;
        vertices.push(Vertex::new(*v0, *normal));
        vertices.push(Vertex::new(*v1, *normal));
        vertices.push(Vertex::new(*v2, *normal));
        vertices.push(Vertex::new(*v3, *normal));
        // Two triangles: 0-1-2, 0-2-3
        indices.extend_from_slice(&[base, base + 1, base + 2, base, base + 2, base + 3]);
    }

    Mesh::new(vertices, indices)
}

/// Create a UV sphere centered at the origin with radius 0.5.
pub fn sphere(stacks: u32, slices: u32) -> Mesh {
    let stacks = stacks.max(3);
    let slices = slices.max(3);

    let mut vertices = Vec::new();
    let mut indices = Vec::new();

    for i in 0..=stacks {
        let phi = std::f32::consts::PI * i as f32 / stacks as f32;
        let y = 0.5 * phi.cos();
        let r = 0.5 * phi.sin();

        for j in 0..=slices {
            let theta = 2.0 * std::f32::consts::PI * j as f32 / slices as f32;
            let x = r * theta.cos();
            let z = r * theta.sin();
            let pos = Vec3::new(x, y, z);
            let normal = pos.normalize();
            let u = j as f32 / slices as f32;
            let v = i as f32 / stacks as f32;
            vertices.push(Vertex::new(pos, normal).with_uv(u, v));
        }
    }

    for i in 0..stacks {
        for j in 0..slices {
            let a = i * (slices + 1) + j;
            let b = a + slices + 1;
            indices.extend_from_slice(&[a, b, a + 1, b, b + 1, a + 1]);
        }
    }

    Mesh::new(vertices, indices)
}

/// Create a flat plane on the XZ plane centered at the origin (side length 1).
pub fn plane() -> Mesh {
    let normal = Vec3::Y;
    let vertices = vec![
        Vertex::new(Vec3::new(-0.5, 0.0, -0.5), normal).with_uv(0.0, 0.0),
        Vertex::new(Vec3::new(0.5, 0.0, -0.5), normal).with_uv(1.0, 0.0),
        Vertex::new(Vec3::new(0.5, 0.0, 0.5), normal).with_uv(1.0, 1.0),
        Vertex::new(Vec3::new(-0.5, 0.0, 0.5), normal).with_uv(0.0, 1.0),
    ];
    let indices = vec![0, 1, 2, 0, 2, 3];
    Mesh::new(vertices, indices)
}
