pub mod render_mode;
pub mod viewport;

// Re-export the entire render3d crate so downstream users
// can use `ratatui_3d::` as a single import path.
pub use render3d::*;

// Extend the prelude with ratatui-specific widget types.
pub mod prelude {
    pub use render3d::prelude::*;
    pub use crate::render_mode::RenderMode;
    pub use crate::viewport::{Viewport3D, Viewport3DState, Viewport3DStatic};
}
