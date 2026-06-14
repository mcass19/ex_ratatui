use crate::color::Rgb;
use crate::light::Light;
use crate::object::SceneObject;

/// Gradient sky: interpolates between zenith (straight up), horizon, and ground (straight down).
#[derive(Debug, Clone, Copy)]
pub struct Sky {
    pub zenith: Rgb,
    pub horizon: Rgb,
    pub ground: Rgb,
}

impl Sky {
    /// Compute sky color for a ray direction.
    pub fn sample(&self, dir_y: f32) -> Rgb {
        if dir_y > 0.0 {
            // Looking up: lerp horizon → zenith
            let t = dir_y.min(1.0);
            self.horizon.lerp(self.zenith, t)
        } else {
            // Looking down: lerp horizon → ground
            let t = (-dir_y).min(1.0);
            self.horizon.lerp(self.ground, t)
        }
    }
}

/// The 3D scene containing objects and lights.
#[derive(Debug, Clone)]
pub struct Scene {
    pub objects: Vec<SceneObject>,
    pub lights: Vec<Light>,
    pub background: Rgb,
    pub sky: Option<Sky>,
}

impl Default for Scene {
    fn default() -> Self {
        Self::new()
    }
}

impl Scene {
    pub fn new() -> Self {
        Self {
            objects: Vec::new(),
            lights: Vec::new(),
            background: Rgb::BLACK,
            sky: None,
        }
    }

    pub fn add_object(&mut self, object: SceneObject) -> &mut Self {
        self.objects.push(object);
        self
    }

    pub fn add_light(&mut self, light: Light) -> &mut Self {
        self.lights.push(light);
        self
    }

    pub fn with_background(mut self, color: Rgb) -> Self {
        self.background = color;
        self
    }

    pub fn with_sky(mut self, sky: Sky) -> Self {
        self.sky = Some(sky);
        self
    }
}
