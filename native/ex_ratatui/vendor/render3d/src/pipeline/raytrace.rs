use crate::camera::{Camera, Projection};
use crate::color::Rgb;
use crate::light::Light;
use crate::material::Material;
use crate::math::Vec3;
use crate::scene::Scene;

use super::Framebuffer;

const EPSILON: f32 = 1e-4;

struct Ray {
    origin: Vec3,
    direction: Vec3,
}

/// Pre-transformed triangle in world space.
struct WorldTri {
    v0: Vec3,
    v1: Vec3,
    v2: Vec3,
    n0: Vec3,
    n1: Vec3,
    n2: Vec3,
    obj_idx: usize,
}

struct Hit {
    position: Vec3,
    normal: Vec3,
    obj_idx: usize,
}

/// Pre-transform all scene triangles into world space.
fn prepare(scene: &Scene) -> Vec<WorldTri> {
    let mut tris = Vec::new();

    for (obj_idx, obj) in scene.objects.iter().enumerate() {
        if !obj.visible {
            continue;
        }

        let model = obj.transform.matrix();
        let normal_mat = model.inverse().transpose();
        let mesh = &obj.mesh;

        for tri in 0..mesh.triangle_count() {
            let i0 = mesh.indices[tri * 3] as usize;
            let i1 = mesh.indices[tri * 3 + 1] as usize;
            let i2 = mesh.indices[tri * 3 + 2] as usize;

            tris.push(WorldTri {
                v0: model.transform_point3(mesh.vertices[i0].position),
                v1: model.transform_point3(mesh.vertices[i1].position),
                v2: model.transform_point3(mesh.vertices[i2].position),
                n0: normal_mat
                    .transform_vector3(mesh.vertices[i0].normal)
                    .normalize_or_zero(),
                n1: normal_mat
                    .transform_vector3(mesh.vertices[i1].normal)
                    .normalize_or_zero(),
                n2: normal_mat
                    .transform_vector3(mesh.vertices[i2].normal)
                    .normalize_or_zero(),
                obj_idx,
            });
        }
    }

    tris
}

/// Möller–Trumbore ray-triangle intersection.
/// Returns (t, u, v) where u,v are barycentric coordinates.
fn ray_tri_test(ray: &Ray, tri: &WorldTri) -> Option<(f32, f32, f32)> {
    let e1 = tri.v1 - tri.v0;
    let e2 = tri.v2 - tri.v0;
    let h = ray.direction.cross(e2);
    let a = e1.dot(h);

    if a.abs() < EPSILON {
        return None;
    }

    let f = 1.0 / a;
    let s = ray.origin - tri.v0;
    let u = f * s.dot(h);

    if !(0.0..=1.0).contains(&u) {
        return None;
    }

    let q = s.cross(e1);
    let v = f * ray.direction.dot(q);

    if v < 0.0 || u + v > 1.0 {
        return None;
    }

    let t = f * e2.dot(q);
    if t > EPSILON {
        Some((t, u, v))
    } else {
        None
    }
}

/// Find the closest intersection along a ray.
fn closest_hit(ray: &Ray, tris: &[WorldTri]) -> Option<Hit> {
    let mut best: Option<Hit> = None;
    let mut min_t = f32::MAX;

    for tri in tris {
        if let Some((t, u, v)) = ray_tri_test(ray, tri) {
            if t < min_t {
                min_t = t;
                let w = 1.0 - u - v;
                let position = ray.origin + ray.direction * t;
                let mut normal = (tri.n0 * w + tri.n1 * u + tri.n2 * v).normalize_or_zero();

                // Flip normal if it faces away from the ray (back-face hit)
                if normal.dot(ray.direction) > 0.0 {
                    normal = -normal;
                }

                best = Some(Hit {
                    position,
                    normal,
                    obj_idx: tri.obj_idx,
                });
            }
        }
    }

    best
}

/// Test if any triangle blocks the ray within max_t distance.
fn any_hit(ray: &Ray, tris: &[WorldTri], max_t: f32) -> bool {
    for tri in tris {
        if let Some((t, _, _)) = ray_tri_test(ray, tri) {
            if t < max_t {
                return true;
            }
        }
    }
    false
}

/// Shade a hit point with Phong lighting and shadow rays.
fn shade(ray: &Ray, hit: &Hit, material: &Material, lights: &[Light], tris: &[WorldTri]) -> Rgb {
    let normal = hit.normal;
    let view_dir = (-ray.direction).normalize();

    let mut total_r: f32 = 0.0;
    let mut total_g: f32 = 0.0;
    let mut total_b: f32 = 0.0;

    let shadow_origin = hit.position + normal * EPSILON;

    for light in lights {
        match light {
            Light::Ambient {
                color,
                intensity,
            } => {
                let factor = intensity * material.ambient;
                total_r += (color.0 as f32 / 255.0) * factor;
                total_g += (color.1 as f32 / 255.0) * factor;
                total_b += (color.2 as f32 / 255.0) * factor;
            }
            Light::Directional {
                direction,
                color,
                intensity,
            } => {
                let light_dir = -*direction;

                // Shadow test
                let shadow_ray = Ray {
                    origin: shadow_origin,
                    direction: light_dir,
                };
                if any_hit(&shadow_ray, tris, f32::MAX) {
                    continue;
                }

                let (dr, dg, db) =
                    phong(normal, light_dir, view_dir, material, *color, *intensity);
                total_r += dr;
                total_g += dg;
                total_b += db;
            }
            Light::Point {
                position: light_pos,
                color,
                intensity,
            } => {
                let to_light = *light_pos - hit.position;
                let distance = to_light.length();
                let light_dir = to_light / distance;

                // Shadow test (only up to the light distance)
                let shadow_ray = Ray {
                    origin: shadow_origin,
                    direction: light_dir,
                };
                if any_hit(&shadow_ray, tris, distance) {
                    continue;
                }

                let attenuation =
                    intensity / (1.0 + 0.09 * distance + 0.032 * distance * distance);
                let (dr, dg, db) =
                    phong(normal, light_dir, view_dir, material, *color, attenuation);
                total_r += dr;
                total_g += dg;
                total_b += db;
            }
        }
    }

    let r = (total_r * material.color.0 as f32).clamp(0.0, 255.0) as u8;
    let g = (total_g * material.color.1 as f32).clamp(0.0, 255.0) as u8;
    let b = (total_b * material.color.2 as f32).clamp(0.0, 255.0) as u8;

    Rgb(r, g, b)
}

/// Diffuse + specular contribution from a single light (Blinn-Phong).
fn phong(
    normal: Vec3,
    light_dir: Vec3,
    view_dir: Vec3,
    material: &Material,
    light_color: Rgb,
    intensity: f32,
) -> (f32, f32, f32) {
    let n_dot_l = normal.dot(light_dir).max(0.0);
    let diffuse = n_dot_l * material.diffuse * intensity;

    let halfway = (light_dir + view_dir).normalize_or_zero();
    let n_dot_h = normal.dot(halfway).max(0.0);
    let specular = n_dot_h.powf(material.shininess) * material.specular * intensity;

    let total = diffuse + specular;
    (
        (light_color.0 as f32 / 255.0) * total,
        (light_color.1 as f32 / 255.0) * total,
        (light_color.2 as f32 / 255.0) * total,
    )
}

/// Generate a camera ray for pixel (x, y).
fn camera_ray(camera: &Camera, x: u32, y: u32, width: u32, height: u32) -> Ray {
    let Projection::Perspective { fov_y, .. } = camera.projection;

    let aspect = width as f32 / height as f32;
    let half_h = (fov_y / 2.0).tan();
    let half_w = half_h * aspect;

    let ndc_x = (2.0 * (x as f32 + 0.5) / width as f32) - 1.0;
    let ndc_y = 1.0 - (2.0 * (y as f32 + 0.5) / height as f32);

    let forward = (camera.target - camera.position).normalize();
    let right = forward.cross(camera.up).normalize();
    let up = right.cross(forward).normalize();

    let direction = (forward + right * (ndc_x * half_w) + up * (ndc_y * half_h)).normalize();

    Ray {
        origin: camera.position,
        direction,
    }
}

/// Ray-trace the scene into the framebuffer.
pub fn render(scene: &Scene, camera: &Camera, fb: &mut Framebuffer) {
    fb.clear(scene.background);

    if fb.width == 0 || fb.height == 0 {
        return;
    }

    let tris = prepare(scene);

    for y in 0..fb.height {
        for x in 0..fb.width {
            let ray = camera_ray(camera, x, y, fb.width, fb.height);
            let idx = fb.index(x, y);

            if let Some(hit) = closest_hit(&ray, &tris) {
                let material = &scene.objects[hit.obj_idx].material;
                fb.color[idx] = shade(&ray, &hit, material, &scene.lights, &tris);
                fb.alpha[idx] = 255;
            } else if let Some(sky) = &scene.sky {
                fb.color[idx] = sky.sample(ray.direction.y);
            }
        }
    }
}
