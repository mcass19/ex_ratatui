pub mod camera;
pub mod color;
pub mod light;
pub mod loader;
pub mod material;
pub mod math;
pub mod mesh;
pub mod object;
pub mod pipeline;
pub mod primitives;
pub mod scene;
pub mod texture;
pub mod transform;

// Re-exports for convenience
pub use camera::{Camera, Projection};
pub use color::Rgb;
pub use light::Light;
pub use material::Material;
pub use mesh::{Mesh, Vertex};
pub use object::SceneObject;
pub use pipeline::Pipeline;
pub use scene::{Scene, Sky};
pub use texture::Texture;
pub use transform::Transform;

/// Prelude for convenient glob imports.
pub mod prelude {
    pub use crate::camera::{Camera, Projection};
    pub use crate::color::Rgb;
    pub use crate::light::Light;
    pub use crate::material::Material;
    pub use crate::math::{Mat4, Quat, Vec3};
    pub use crate::mesh::{Mesh, Vertex};
    pub use crate::object::SceneObject;
    pub use crate::pipeline::Pipeline;
    pub use crate::primitives;
    pub use crate::scene::{Scene, Sky};
    pub use crate::texture::Texture;
    pub use crate::transform::Transform;
}
