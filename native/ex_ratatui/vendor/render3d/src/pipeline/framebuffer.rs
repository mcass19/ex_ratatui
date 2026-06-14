use crate::color::Rgb;

/// A pixel framebuffer with color, depth, and alpha.
pub struct Framebuffer {
    pub width: u32,
    pub height: u32,
    pub color: Vec<Rgb>,
    pub depth: Vec<f32>,
    /// Per-pixel alpha: 0 = background (transparent), 255 = geometry hit (opaque).
    pub alpha: Vec<u8>,
}

impl Framebuffer {
    pub fn new(width: u32, height: u32) -> Self {
        let size = (width * height) as usize;
        Self {
            width,
            height,
            color: vec![Rgb::BLACK; size],
            depth: vec![f32::INFINITY; size],
            alpha: vec![0; size],
        }
    }

    /// Resize the framebuffer, clearing all data.
    pub fn resize(&mut self, width: u32, height: u32) {
        self.width = width;
        self.height = height;
        let size = (width * height) as usize;
        self.color.resize(size, Rgb::BLACK);
        self.depth.resize(size, f32::INFINITY);
        self.alpha.resize(size, 0);
    }

    /// Clear the framebuffer with a background color.
    pub fn clear(&mut self, bg: Rgb) {
        self.color.fill(bg);
        self.depth.fill(f32::INFINITY);
        self.alpha.fill(0);
    }

    /// Get the index for pixel (x, y).
    #[inline(always)]
    pub fn index(&self, x: u32, y: u32) -> usize {
        (y * self.width + x) as usize
    }

    /// Set a pixel if it passes the depth test.
    #[inline(always)]
    pub fn set_pixel(&mut self, x: u32, y: u32, depth: f32, color: Rgb) {
        if x >= self.width || y >= self.height {
            return;
        }
        let idx = self.index(x, y);
        if depth < self.depth[idx] {
            self.depth[idx] = depth;
            self.color[idx] = color;
            self.alpha[idx] = 255;
        }
    }

    /// Get the color at a pixel.
    pub fn get_pixel(&self, x: u32, y: u32) -> Rgb {
        self.color[self.index(x, y)]
    }
}
