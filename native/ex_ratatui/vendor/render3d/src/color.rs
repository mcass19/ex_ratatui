use std::ops;

/// RGB color with 8-bit channels.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rgb(pub u8, pub u8, pub u8);

impl Rgb {
    pub const BLACK: Self = Self(0, 0, 0);
    pub const WHITE: Self = Self(255, 255, 255);

    /// Linear interpolation between two colors.
    pub fn lerp(self, other: Self, t: f32) -> Self {
        let t = t.clamp(0.0, 1.0);
        Self(
            (self.0 as f32 + (other.0 as f32 - self.0 as f32) * t) as u8,
            (self.1 as f32 + (other.1 as f32 - self.1 as f32) * t) as u8,
            (self.2 as f32 + (other.2 as f32 - self.2 as f32) * t) as u8,
        )
    }

    /// Multiply color by a scalar (for lighting).
    pub fn scale(self, s: f32) -> Self {
        Self(
            (self.0 as f32 * s).clamp(0.0, 255.0) as u8,
            (self.1 as f32 * s).clamp(0.0, 255.0) as u8,
            (self.2 as f32 * s).clamp(0.0, 255.0) as u8,
        )
    }

    /// Component-wise multiply (for tinting).
    pub fn tint(self, other: Self) -> Self {
        Self(
            ((self.0 as u16 * other.0 as u16) / 255) as u8,
            ((self.1 as u16 * other.1 as u16) / 255) as u8,
            ((self.2 as u16 * other.2 as u16) / 255) as u8,
        )
    }

    /// Luminance (perceived brightness).
    pub fn luminance(self) -> f32 {
        (0.299 * self.0 as f32 + 0.587 * self.1 as f32 + 0.114 * self.2 as f32) / 255.0
    }

}

impl ops::Add for Rgb {
    type Output = Self;

    fn add(self, other: Self) -> Self {
        Self(
            self.0.saturating_add(other.0),
            self.1.saturating_add(other.1),
            self.2.saturating_add(other.2),
        )
    }
}
