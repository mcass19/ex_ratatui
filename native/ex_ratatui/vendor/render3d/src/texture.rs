use crate::color::Rgb;

/// A 2D texture with RGBA pixel data.
#[derive(Debug, Clone)]
pub struct Texture {
    pub width: u32,
    pub height: u32,
    /// RGBA pixel data, row-major, 4 bytes per pixel.
    pub data: Vec<u8>,
}

impl Texture {
    pub fn from_rgba(width: u32, height: u32, data: Vec<u8>) -> Self {
        debug_assert_eq!(data.len(), (width * height * 4) as usize);
        Self { width, height, data }
    }

    /// Sample the texture at UV coordinates with bilinear filtering.
    /// UV wraps in [0, 1].
    pub fn sample(&self, u: f32, v: f32) -> Rgb {
        let u = u.rem_euclid(1.0);
        let v = v.rem_euclid(1.0);

        let x = u * (self.width as f32 - 1.0);
        let y = v * (self.height as f32 - 1.0);

        let x0 = x.floor() as u32;
        let y0 = y.floor() as u32;
        let x1 = (x0 + 1).min(self.width - 1);
        let y1 = (y0 + 1).min(self.height - 1);

        let fx = x - x0 as f32;
        let fy = y - y0 as f32;

        let c00 = self.pixel(x0, y0);
        let c10 = self.pixel(x1, y0);
        let c01 = self.pixel(x0, y1);
        let c11 = self.pixel(x1, y1);

        let r = (c00.0 as f32 * (1.0 - fx) * (1.0 - fy)
            + c10.0 as f32 * fx * (1.0 - fy)
            + c01.0 as f32 * (1.0 - fx) * fy
            + c11.0 as f32 * fx * fy) as u8;
        let g = (c00.1 as f32 * (1.0 - fx) * (1.0 - fy)
            + c10.1 as f32 * fx * (1.0 - fy)
            + c01.1 as f32 * (1.0 - fx) * fy
            + c11.1 as f32 * fx * fy) as u8;
        let b = (c00.2 as f32 * (1.0 - fx) * (1.0 - fy)
            + c10.2 as f32 * fx * (1.0 - fy)
            + c01.2 as f32 * (1.0 - fx) * fy
            + c11.2 as f32 * fx * fy) as u8;

        Rgb(r, g, b)
    }

    #[inline]
    fn pixel(&self, x: u32, y: u32) -> Rgb {
        let idx = ((y * self.width + x) * 4) as usize;
        Rgb(self.data[idx], self.data[idx + 1], self.data[idx + 2])
    }
}
