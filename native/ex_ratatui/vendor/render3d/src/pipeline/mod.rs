pub mod fragment;
pub mod framebuffer;
pub mod rasterize;
pub mod raytrace;
#[cfg(feature = "gpu")]
pub mod raytrace_gpu;
pub mod vertex;

use crate::camera::Camera;
use crate::scene::Scene;
use rasterize::rasterize_triangle;
use vertex::transform_vertex;

pub use framebuffer::Framebuffer;

/// Which rendering pipeline to use.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Pipeline {
    /// Scanline rasterization (fast).
    #[default]
    Rasterize,
    /// Ray tracing with shadows (slower, more realistic).
    Raytrace,
    /// GPU-accelerated ray tracing via wgpu compute shaders.
    #[cfg(feature = "gpu")]
    RaytraceGpu,
}

/// Execute the full rendering pipeline for a scene.
pub fn render(scene: &Scene, camera: &Camera, fb: &mut Framebuffer) {
    fb.clear(scene.background);

    let vw = fb.width as f32;
    let vh = fb.height as f32;

    if vw < 1.0 || vh < 1.0 {
        return;
    }

    let aspect = vw / vh;
    let view = camera.view_matrix();
    let proj = camera.projection_matrix(aspect);
    let view_proj = proj * view;

    for obj in &scene.objects {
        if !obj.visible {
            continue;
        }

        let model = obj.transform.matrix();
        // Normal matrix: transpose of inverse of upper-left 3x3 of model matrix.
        // For uniform scaling, model itself works. For non-uniform, we need the inverse transpose.
        let normal_matrix = model.inverse().transpose();

        let mesh = &obj.mesh;

        for tri in 0..mesh.triangle_count() {
            let i0 = mesh.indices[tri * 3] as usize;
            let i1 = mesh.indices[tri * 3 + 1] as usize;
            let i2 = mesh.indices[tri * 3 + 2] as usize;

            let vert0 = &mesh.vertices[i0];
            let vert1 = &mesh.vertices[i1];
            let vert2 = &mesh.vertices[i2];

            // Transform vertices
            let tv0 = transform_vertex(
                vert0.position,
                vert0.normal,
                vert0.uv,
                &model,
                &view_proj,
                &normal_matrix,
                vw,
                vh,
            );
            let tv1 = transform_vertex(
                vert1.position,
                vert1.normal,
                vert1.uv,
                &model,
                &view_proj,
                &normal_matrix,
                vw,
                vh,
            );
            let tv2 = transform_vertex(
                vert2.position,
                vert2.normal,
                vert2.uv,
                &model,
                &view_proj,
                &normal_matrix,
                vw,
                vh,
            );

            // Skip if any vertex is behind the camera
            if let (Some(tv0), Some(tv1), Some(tv2)) = (tv0, tv1, tv2) {
                // Simple clip: skip if all vertices are outside NDC range
                let all_outside = (tv0.screen_pos.x < 0.0
                    && tv1.screen_pos.x < 0.0
                    && tv2.screen_pos.x < 0.0)
                    || (tv0.screen_pos.x > vw
                        && tv1.screen_pos.x > vw
                        && tv2.screen_pos.x > vw)
                    || (tv0.screen_pos.y < 0.0
                        && tv1.screen_pos.y < 0.0
                        && tv2.screen_pos.y < 0.0)
                    || (tv0.screen_pos.y > vh
                        && tv1.screen_pos.y > vh
                        && tv2.screen_pos.y > vh);

                if !all_outside {
                    rasterize_triangle(
                        &tv0,
                        &tv1,
                        &tv2,
                        &obj.material,
                        &scene.lights,
                        camera.position,
                        fb,
                    );
                }
            }
        }
    }
}

