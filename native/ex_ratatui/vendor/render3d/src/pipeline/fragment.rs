use crate::color::Rgb;
use crate::light::Light;
use crate::material::Material;
use crate::math::Vec3;

/// Phong shading: compute the final color for a fragment.
///
/// All light contributions are accumulated in normalized [0, 1+] space,
/// then multiplied by the material base color and clamped to [0, 255].
pub fn shade_fragment(
    world_pos: Vec3,
    world_normal: Vec3,
    base_color: Rgb,
    material: &Material,
    lights: &[Light],
    camera_pos: Vec3,
) -> Rgb {
    let normal = world_normal;
    let view_dir = (camera_pos - world_pos).normalize_or_zero();

    // Accumulate light intensity per channel in [0, ∞) normalized range
    let mut total_r: f32 = 0.0;
    let mut total_g: f32 = 0.0;
    let mut total_b: f32 = 0.0;

    for light in lights {
        match light {
            Light::Ambient { color, intensity } => {
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
                let (dr, dg, db) =
                    diffuse_specular(normal, light_dir, view_dir, material, *color, *intensity);
                total_r += dr;
                total_g += dg;
                total_b += db;
            }
            Light::Point {
                position,
                color,
                intensity,
            } => {
                let to_light = *position - world_pos;
                let distance = to_light.length();
                let light_dir = to_light / distance;
                let attenuation =
                    intensity / (1.0 + 0.09 * distance + 0.032 * distance * distance);
                let (dr, dg, db) =
                    diffuse_specular(normal, light_dir, view_dir, material, *color, attenuation);
                total_r += dr;
                total_g += dg;
                total_b += db;
            }
        }
    }

    // Multiply accumulated light by base color
    let r = (total_r * base_color.0 as f32).clamp(0.0, 255.0) as u8;
    let g = (total_g * base_color.1 as f32).clamp(0.0, 255.0) as u8;
    let b = (total_b * base_color.2 as f32).clamp(0.0, 255.0) as u8;

    Rgb(r, g, b)
}

/// Compute diffuse + specular contribution from a single light direction.
/// Returns normalized [0, 1+] RGB contribution.
fn diffuse_specular(
    normal: Vec3,
    light_dir: Vec3,
    view_dir: Vec3,
    material: &Material,
    light_color: Rgb,
    intensity: f32,
) -> (f32, f32, f32) {
    // Diffuse (Lambert)
    let n_dot_l = normal.dot(light_dir).max(0.0);
    let diffuse = n_dot_l * material.diffuse * intensity;

    // Specular (Blinn-Phong)
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
