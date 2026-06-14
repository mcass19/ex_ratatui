pub use glam::{Mat4, Quat, Vec2, Vec3, Vec4};

/// Construct a perspective projection matrix.
pub fn perspective(fov_y_radians: f32, aspect: f32, z_near: f32, z_far: f32) -> Mat4 {
    Mat4::perspective_rh(fov_y_radians, aspect, z_near, z_far)
}

/// Construct a look-at view matrix (right-handed).
pub fn look_at(eye: Vec3, target: Vec3, up: Vec3) -> Mat4 {
    Mat4::look_at_rh(eye, target, up)
}
