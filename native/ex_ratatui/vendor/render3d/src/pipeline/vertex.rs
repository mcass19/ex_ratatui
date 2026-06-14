use crate::math::{Mat4, Vec3, Vec4};

/// A vertex transformed through the pipeline stages.
#[derive(Debug, Clone, Copy)]
pub struct TransformedVertex {
    /// Screen-space position (x, y in pixels, z = depth 0..1).
    pub screen_pos: Vec3,
    /// World-space position (for lighting calculations).
    pub world_pos: Vec3,
    /// World-space normal (for lighting calculations).
    pub world_normal: Vec3,
    /// Texture coordinates.
    pub uv: [f32; 2],
}

/// Transform a vertex from model space through the full pipeline.
///
/// Returns `None` if the vertex is behind the near plane (w <= 0).
pub fn transform_vertex(
    position: Vec3,
    normal: Vec3,
    uv: [f32; 2],
    model: &Mat4,
    view_proj: &Mat4,
    normal_matrix: &Mat4,
    viewport_width: f32,
    viewport_height: f32,
) -> Option<TransformedVertex> {
    // Model → World
    let world_pos = model.transform_point3(position);
    let world_normal = normal_matrix.transform_vector3(normal).normalize_or_zero();

    // World → Clip
    let clip = *view_proj * Vec4::new(world_pos.x, world_pos.y, world_pos.z, 1.0);

    // Behind camera check
    if clip.w <= 0.0 {
        return None;
    }

    // Perspective divide → NDC [-1, 1]
    let ndc = Vec3::new(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w);

    // NDC → Screen coordinates
    let screen_x = (ndc.x + 1.0) * 0.5 * viewport_width;
    let screen_y = (1.0 - ndc.y) * 0.5 * viewport_height; // flip Y for screen
    let screen_z = (ndc.z + 1.0) * 0.5; // map to [0, 1]

    Some(TransformedVertex {
        screen_pos: Vec3::new(screen_x, screen_y, screen_z),
        world_pos,
        world_normal,
        uv,
    })
}
