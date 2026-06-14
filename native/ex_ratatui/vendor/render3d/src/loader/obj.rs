use crate::math::Vec3;
use crate::mesh::{compute_normals, Mesh, Vertex};
use std::path::Path;

/// Load meshes from an OBJ file. Returns one `Mesh` per model in the file.
pub fn load_obj(path: impl AsRef<Path>) -> Result<Vec<Mesh>, String> {
    let (models, _materials) =
        tobj::load_obj(path.as_ref(), &tobj::GPU_LOAD_OPTIONS).map_err(|e| e.to_string())?;

    let mut meshes = Vec::with_capacity(models.len());

    for model in &models {
        let m = &model.mesh;
        let mut vertices = Vec::with_capacity(m.positions.len() / 3);
        let has_normals = !m.normals.is_empty();

        for i in 0..(m.positions.len() / 3) {
            let pos = Vec3::new(m.positions[i * 3], m.positions[i * 3 + 1], m.positions[i * 3 + 2]);
            let normal = if has_normals {
                Vec3::new(m.normals[i * 3], m.normals[i * 3 + 1], m.normals[i * 3 + 2])
            } else {
                Vec3::ZERO
            };
            let mut v = Vertex::new(pos, normal);
            if !m.texcoords.is_empty() && i * 2 + 1 < m.texcoords.len() {
                v = v.with_uv(m.texcoords[i * 2], m.texcoords[i * 2 + 1]);
            }
            vertices.push(v);
        }

        // Compute face normals if normals weren't provided
        if !has_normals {
            compute_normals(&mut vertices, &m.indices);
        }

        meshes.push(Mesh::new(vertices, m.indices.clone()));
    }

    Ok(meshes)
}
