use render3d::camera::Camera;
use render3d::pipeline::{self, Framebuffer, Pipeline};
use crate::render_mode::RenderMode;
use render3d::scene::Scene;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::widgets::{Block, StatefulWidget, Widget};

/// Persistent state for the 3D viewport, owned by the app.
pub struct Viewport3DState {
    pub camera: Camera,
    pub render_mode: RenderMode,
    pub pipeline: Pipeline,
    framebuffer: Framebuffer,
    #[cfg(feature = "gpu")]
    gpu_renderer: Option<pipeline::raytrace_gpu::GpuRenderer>,
}

impl Default for Viewport3DState {
    fn default() -> Self {
        Self {
            camera: Camera::default(),
            render_mode: RenderMode::default(),
            pipeline: Pipeline::default(),
            framebuffer: Framebuffer::new(0, 0),
            #[cfg(feature = "gpu")]
            gpu_renderer: None,
        }
    }
}

impl Viewport3DState {
    pub fn new(camera: Camera, render_mode: RenderMode) -> Self {
        Self {
            camera,
            render_mode,
            pipeline: Pipeline::default(),
            framebuffer: Framebuffer::new(0, 0),
            #[cfg(feature = "gpu")]
            gpu_renderer: None,
        }
    }
}

/// Ephemeral widget that renders a 3D scene into a terminal area.
pub struct Viewport3D<'a> {
    scene: &'a Scene,
    block: Option<Block<'a>>,
}

impl<'a> Viewport3D<'a> {
    pub fn new(scene: &'a Scene) -> Self {
        Self { scene, block: None }
    }

    pub fn block(mut self, block: Block<'a>) -> Self {
        self.block = Some(block);
        self
    }
}

impl<'a> StatefulWidget for Viewport3D<'a> {
    type State = Viewport3DState;

    fn render(self, area: Rect, buf: &mut Buffer, state: &mut Self::State) {
        // Render block border first, get inner area
        let inner = if let Some(block) = &self.block {
            let inner = block.inner(area);
            block.clone().render(area, buf);
            inner
        } else {
            area
        };

        if inner.width == 0 || inner.height == 0 {
            return;
        }

        // Compute pixel resolution based on render mode
        let (pw, ph) = state.render_mode.pixel_size(inner);

        // Resize framebuffer if needed
        if state.framebuffer.width != pw || state.framebuffer.height != ph {
            state.framebuffer.resize(pw, ph);
        }

        // Run the rendering pipeline
        match state.pipeline {
            Pipeline::Rasterize => {
                pipeline::render(self.scene, &state.camera, &mut state.framebuffer)
            }
            Pipeline::Raytrace => {
                pipeline::raytrace::render(self.scene, &state.camera, &mut state.framebuffer)
            }
            #[cfg(feature = "gpu")]
            Pipeline::RaytraceGpu => {
                let renderer = state
                    .gpu_renderer
                    .get_or_insert_with(pipeline::raytrace_gpu::GpuRenderer::new);
                renderer.render(self.scene, &state.camera, &mut state.framebuffer);
            }
        }

        // Blit framebuffer to terminal cells
        state.render_mode.blit(&state.framebuffer, inner, buf);
    }
}

/// Non-stateful widget for one-shot static renders.
pub struct Viewport3DStatic<'a> {
    scene: &'a Scene,
    camera: Camera,
    render_mode: RenderMode,
    block: Option<Block<'a>>,
}

impl<'a> Viewport3DStatic<'a> {
    pub fn new(scene: &'a Scene, camera: Camera) -> Self {
        Self {
            scene,
            camera,
            render_mode: RenderMode::default(),
            block: None,
        }
    }

    pub fn render_mode(mut self, mode: RenderMode) -> Self {
        self.render_mode = mode;
        self
    }

    pub fn block(mut self, block: Block<'a>) -> Self {
        self.block = Some(block);
        self
    }
}

impl<'a> Widget for Viewport3DStatic<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let mut state = Viewport3DState::new(self.camera, self.render_mode);
        let viewport = Viewport3D {
            scene: self.scene,
            block: self.block,
        };
        StatefulWidget::render(viewport, area, buf, &mut state);
    }
}
