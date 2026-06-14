use crate::color::Rgb;
use crate::math::Vec3;
use crate::pipeline::fragment::shade_fragment;
use crate::pipeline::framebuffer::Framebuffer;
use crate::pipeline::vertex::TransformedVertex;
use crate::{Light, Material};

/// Rasterize a single triangle into the framebuffer.
pub fn rasterize_triangle(
    v0: &TransformedVertex,
    v1: &TransformedVertex,
    v2: &TransformedVertex,
    material: &Material,
    lights: &[Light],
    camera_pos: Vec3,
    fb: &mut Framebuffer,
) {
    let p0 = v0.screen_pos;
    let p1 = v1.screen_pos;
    let p2 = v2.screen_pos;

    // Signed area via 2D cross product
    let edge1 = p1 - p0;
    let edge2 = p2 - p0;
    let cross_z = edge1.x * edge2.y - edge1.y * edge2.x;

    // After viewport Y-flip, front-facing (originally CCW) triangles have negative cross_z.
    // Positive cross_z = back-facing → cull.
    if cross_z >= 0.0 {
        return;
    }

    // Bounding box (clamped to framebuffer)
    let min_x = p0.x.min(p1.x).min(p2.x).max(0.0) as u32;
    let max_x = p0.x.max(p1.x).max(p2.x).min(fb.width as f32 - 1.0) as u32;
    let min_y = p0.y.min(p1.y).min(p2.y).max(0.0) as u32;
    let max_y = p0.y.max(p1.y).max(p2.y).min(fb.height as f32 - 1.0) as u32;

    if min_x > max_x || min_y > max_y {
        return;
    }

    // cross_z is negative for front-facing triangles (after Y-flip).
    // Edge functions for interior points are POSITIVE (opposite sign of cross_z).
    // Negate cross_z for a positive area divisor so barycentrics come out positive.
    let inv_area = -1.0 / cross_z;

    for y in min_y..=max_y {
        for x in min_x..=max_x {
            let px = x as f32 + 0.5;
            let py = y as f32 + 0.5;

            // Edge functions — positive for interior points (since cross_z < 0)
            let w0 = edge_function(p1, p2, px, py);
            let w1 = edge_function(p2, p0, px, py);
            let w2 = edge_function(p0, p1, px, py);

            if w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0 {
                let b0 = w0 * inv_area;
                let b1 = w1 * inv_area;
                let b2 = w2 * inv_area;

                // Interpolate depth
                let depth = b0 * p0.z + b1 * p1.z + b2 * p2.z;

                // Early depth test
                let idx = fb.index(x, y);
                if depth >= fb.depth[idx] {
                    continue;
                }

                // Interpolate world-space attributes
                let world_pos =
                    v0.world_pos * b0 + v1.world_pos * b1 + v2.world_pos * b2;
                let world_normal =
                    (v0.world_normal * b0 + v1.world_normal * b1 + v2.world_normal * b2)
                        .normalize_or_zero();

                // Interpolate UV and determine base color
                let base_color = if let Some(tex) = &material.texture {
                    let u = v0.uv[0] * b0 + v1.uv[0] * b1 + v2.uv[0] * b2;
                    let v = v0.uv[1] * b0 + v1.uv[1] * b1 + v2.uv[1] * b2;
                    tex.sample(u, v)
                } else {
                    material.color
                };

                // Fragment shading
                let color =
                    shade_fragment(world_pos, world_normal, base_color, material, lights, camera_pos);

                fb.depth[idx] = depth;
                fb.color[idx] = color;
                fb.alpha[idx] = 255;
            }
        }
    }
}

/// Signed area of the parallelogram formed by edge (a→b) and point p.
#[inline(always)]
fn edge_function(a: Vec3, b: Vec3, px: f32, py: f32) -> f32 {
    (px - a.x) * (b.y - a.y) - (py - a.y) * (b.x - a.x)
}

/// Rasterize a wireframe triangle (for debugging).
pub fn rasterize_wireframe(
    v0: &TransformedVertex,
    v1: &TransformedVertex,
    v2: &TransformedVertex,
    color: Rgb,
    fb: &mut Framebuffer,
) {
    draw_line(v0.screen_pos, v1.screen_pos, color, fb);
    draw_line(v1.screen_pos, v2.screen_pos, color, fb);
    draw_line(v2.screen_pos, v0.screen_pos, color, fb);
}

fn draw_line(a: Vec3, b: Vec3, color: Rgb, fb: &mut Framebuffer) {
    let dx = (b.x - a.x).abs();
    let dy = (b.y - a.y).abs();
    let steps = dx.max(dy) as u32;
    if steps == 0 {
        return;
    }
    for i in 0..=steps {
        let t = i as f32 / steps as f32;
        let x = (a.x + (b.x - a.x) * t) as u32;
        let y = (a.y + (b.y - a.y) * t) as u32;
        let depth = a.z + (b.z - a.z) * t;
        fb.set_pixel(x, y, depth, color);
    }
}
