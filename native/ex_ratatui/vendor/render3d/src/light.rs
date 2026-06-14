use crate::color::Rgb;
use crate::math::Vec3;

/// A light source in the scene.
#[derive(Debug, Clone, Copy)]
pub enum Light {
    /// Constant ambient illumination.
    Ambient { color: Rgb, intensity: f32 },
    /// Directional light (like the sun). Direction points *toward* the light source.
    Directional {
        direction: Vec3,
        color: Rgb,
        intensity: f32,
    },
    /// Point light with attenuation.
    Point {
        position: Vec3,
        color: Rgb,
        intensity: f32,
    },
}

impl Light {
    pub fn ambient(color: Rgb, intensity: f32) -> Self {
        Self::Ambient { color, intensity }
    }

    pub fn directional(direction: Vec3, color: Rgb) -> Self {
        Self::Directional {
            direction: direction.normalize(),
            color,
            intensity: 1.0,
        }
    }

    pub fn point(position: Vec3, color: Rgb) -> Self {
        Self::Point {
            position,
            color,
            intensity: 1.0,
        }
    }
}
