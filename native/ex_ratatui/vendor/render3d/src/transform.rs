use crate::math::{Mat4, Quat, Vec3};

/// Position, rotation, and scale of an object in the scene.
#[derive(Debug, Clone, Copy)]
pub struct Transform {
    pub position: Vec3,
    pub rotation: Quat,
    pub scale: Vec3,
}

impl Default for Transform {
    fn default() -> Self {
        Self {
            position: Vec3::ZERO,
            rotation: Quat::IDENTITY,
            scale: Vec3::ONE,
        }
    }
}

impl Transform {
    pub fn from_position(position: Vec3) -> Self {
        Self {
            position,
            ..Default::default()
        }
    }

    /// Compose a 4×4 model matrix: scale → rotate → translate.
    pub fn matrix(&self) -> Mat4 {
        Mat4::from_scale_rotation_translation(self.scale, self.rotation, self.position)
    }
}
