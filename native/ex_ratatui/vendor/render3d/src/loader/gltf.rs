use crate::math::Vec3;
use crate::mesh::{compute_normals, Mesh, Vertex};
use std::path::Path;

/// Load meshes from a glTF or glB file. Returns one `Mesh` per primitive.
pub fn load_gltf(path: impl AsRef<Path>) -> Result<Vec<Mesh>, String> {
    let (document, buffers, _images) =
        ::gltf::import(path).map_err(|e| e.to_string())?;

    let mut meshes = Vec::new();

    for mesh in document.meshes() {
        for primitive in mesh.primitives() {
            let reader = primitive.reader(|buffer| Some(&buffers[buffer.index()]));

            // Read positions (required)
            let positions: Vec<[f32; 3]> = reader
                .read_positions()
                .ok_or_else(|| "Primitive missing positions".to_string())?
                .collect();

            // Read normals (optional)
            let normals: Option<Vec<[f32; 3]>> =
                reader.read_normals().map(|iter| iter.collect());

            // Read tex coords (optional, first set)
            let tex_coords: Option<Vec<[f32; 2]>> = reader
                .read_tex_coords(0)
                .map(|iter| iter.into_f32().collect());

            // Read indices (optional)
            let indices: Vec<u32> = match reader.read_indices() {
                Some(read_indices) => read_indices.into_u32().collect(),
                None => (0..positions.len() as u32).collect(),
            };

            // Build vertices
            let has_normals = normals.is_some();
            let normals_ref = normals.as_deref();
            let tex_coords_ref = tex_coords.as_deref();

            let mut vertices = Vec::with_capacity(positions.len());
            for (i, pos) in positions.iter().enumerate() {
                let position = Vec3::new(pos[0], pos[1], pos[2]);
                let normal = normals_ref
                    .and_then(|n| n.get(i))
                    .map(|n| Vec3::new(n[0], n[1], n[2]))
                    .unwrap_or(Vec3::ZERO);
                let mut v = Vertex::new(position, normal);
                if let Some(uv) = tex_coords_ref.and_then(|t| t.get(i)) {
                    v = v.with_uv(uv[0], uv[1]);
                }
                vertices.push(v);
            }

            if !has_normals {
                compute_normals(&mut vertices, &indices);
            }

            meshes.push(Mesh::new(vertices, indices));
        }
    }

    Ok(meshes)
}
