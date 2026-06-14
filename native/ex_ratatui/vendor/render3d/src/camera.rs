use crate::math::{Mat4, Vec3};

/// Projection type for the camera.
#[derive(Debug, Clone, Copy)]
pub enum Projection {
    Perspective {
        fov_y: f32,
        near: f32,
        far: f32,
    },
}

impl Default for Projection {
    fn default() -> Self {
        Self::Perspective {
            fov_y: std::f32::consts::FRAC_PI_4,
            near: 0.1,
            far: 100.0,
        }
    }
}

/// A camera that defines the view into the 3D scene.
#[derive(Debug, Clone)]
pub struct Camera {
    pub position: Vec3,
    pub target: Vec3,
    pub up: Vec3,
    pub projection: Projection,
}

impl Default for Camera {
    fn default() -> Self {
        Self {
            position: Vec3::new(0.0, 2.0, 5.0),
            target: Vec3::ZERO,
            up: Vec3::Y,
            projection: Projection::default(),
        }
    }
}

impl Camera {
    /// Compute the view matrix.
    pub fn view_matrix(&self) -> Mat4 {
        Mat4::look_at_rh(self.position, self.target, self.up)
    }

    /// Compute the projection matrix for a given aspect ratio.
    pub fn projection_matrix(&self, aspect: f32) -> Mat4 {
        match self.projection {
            Projection::Perspective { fov_y, near, far } => {
                Mat4::perspective_rh(fov_y, aspect, near, far)
            }
        }
    }

    /// Orbit the camera around the target by yaw/pitch deltas (radians).
    pub fn orbit(&mut self, yaw: f32, pitch: f32) {
        let offset = self.position - self.target;
        let radius = offset.length();

        // Current spherical coordinates
        let theta = offset.z.atan2(offset.x) + yaw;
        let phi = (offset.y / radius).acos() + pitch;

        // Clamp phi to avoid gimbal lock
        let phi = phi.clamp(0.05, std::f32::consts::PI - 0.05);

        self.position = self.target
            + Vec3::new(
                radius * phi.sin() * theta.cos(),
                radius * phi.cos(),
                radius * phi.sin() * theta.sin(),
            );
    }

    /// Zoom (move camera closer/further from target).
    pub fn zoom(&mut self, delta: f32) {
        let offset = self.position - self.target;
        let radius = (offset.length() + delta).max(0.5);
        self.position = self.target + offset.normalize() * radius;
    }
}
