use std::sync::Arc;

use crate::color::Rgb;
use crate::texture::Texture;

/// Surface material properties for Phong shading.
#[derive(Debug, Clone)]
pub struct Material {
    pub color: Rgb,
    pub ambient: f32,
    pub diffuse: f32,
    pub specular: f32,
    pub shininess: f32,
    pub texture: Option<Arc<Texture>>,
}

impl Default for Material {
    fn default() -> Self {
        Self {
            color: Rgb(200, 200, 200),
            ambient: 0.1,
            diffuse: 0.8,
            specular: 0.5,
            shininess: 32.0,
            texture: None,
        }
    }
}

impl Material {
    pub fn with_color(mut self, color: Rgb) -> Self {
        self.color = color;
        self
    }

    pub fn with_ambient(mut self, ambient: f32) -> Self {
        self.ambient = ambient;
        self
    }

    pub fn with_diffuse(mut self, diffuse: f32) -> Self {
        self.diffuse = diffuse;
        self
    }

    pub fn with_specular(mut self, specular: f32) -> Self {
        self.specular = specular;
        self
    }

    pub fn with_shininess(mut self, shininess: f32) -> Self {
        self.shininess = shininess;
        self
    }

    pub fn with_texture(mut self, texture: Arc<Texture>) -> Self {
        self.texture = Some(texture);
        self
    }
}
