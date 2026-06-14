use render3d::color::Rgb;
use render3d::pipeline::framebuffer::Framebuffer;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::{Color, Style};

/// How the framebuffer pixels are mapped to terminal cells.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum RenderMode {
    /// Half-block characters: 2 vertical pixels per cell using ▀ with fg=upper, bg=lower.
    HalfBlock,
    /// Supersampled half-block: 2×4 pixels per cell averaged into ▀, giving anti-aliased edges.
    #[default]
    Braille,
    /// ASCII shading ramp with colored characters.
    Ascii,
}

impl RenderMode {
    /// Compute the pixel resolution for a given terminal area.
    pub fn pixel_size(self, area: Rect) -> (u32, u32) {
        match self {
            RenderMode::HalfBlock => (area.width as u32, area.height as u32 * 2),
            RenderMode::Braille => (area.width as u32 * 2, area.height as u32 * 4),
            RenderMode::Ascii => (area.width as u32, area.height as u32 * 2),
        }
    }

    /// Blit the framebuffer into the ratatui buffer.
    pub fn blit(self, fb: &Framebuffer, area: Rect, buf: &mut Buffer) {
        match self {
            RenderMode::HalfBlock => blit_half_block(fb, area, buf),
            RenderMode::Braille => blit_braille(fb, area, buf),
            RenderMode::Ascii => blit_ascii(fb, area, buf),
        }
    }
}

/// Half-block blit: use ▀ (upper half block) with fg = upper pixel, bg = lower pixel.
fn blit_half_block(fb: &Framebuffer, area: Rect, buf: &mut Buffer) {
    for row in 0..area.height {
        for col in 0..area.width {
            let px = col as u32;
            let py_upper = row as u32 * 2;
            let py_lower = py_upper + 1;

            let upper = if px < fb.width && py_upper < fb.height {
                fb.get_pixel(px, py_upper)
            } else {
                Rgb::BLACK
            };

            let lower = if px < fb.width && py_lower < fb.height {
                fb.get_pixel(px, py_lower)
            } else {
                Rgb::BLACK
            };

            let cell = &mut buf[(area.x + col, area.y + row)];
            cell.set_char('▀');
            cell.set_style(
                Style::default()
                    .fg(Color::Rgb(upper.0, upper.1, upper.2))
                    .bg(Color::Rgb(lower.0, lower.1, lower.2)),
            );
        }
    }
}

/// Supersampled half-block blit: renders at 2×4 pixel resolution per cell
/// (same as braille) but displays using ▀ half-block characters.
/// Top 2 rows of pixels (4 samples) are averaged for fg, bottom 2 rows for bg.
/// This gives anti-aliased edges with 2× horizontal supersampling — smoother
/// than standard half-block without the visual artifacts of braille dots.
fn blit_braille(fb: &Framebuffer, area: Rect, buf: &mut Buffer) {
    for row in 0..area.height {
        for col in 0..area.width {
            let base_x = col as u32 * 2;
            let base_y = row as u32 * 4;

            // Top half: rows 0-1 (2 rows × 2 cols = 4 pixels)
            let mut top_r: u32 = 0;
            let mut top_g: u32 = 0;
            let mut top_b: u32 = 0;
            let mut top_n: u32 = 0;

            // Bottom half: rows 2-3 (2 rows × 2 cols = 4 pixels)
            let mut bot_r: u32 = 0;
            let mut bot_g: u32 = 0;
            let mut bot_b: u32 = 0;
            let mut bot_n: u32 = 0;

            for dx in 0..2u32 {
                for dy in 0..4u32 {
                    let px = base_x + dx;
                    let py = base_y + dy;
                    let color = if px < fb.width && py < fb.height {
                        fb.get_pixel(px, py)
                    } else {
                        Rgb::BLACK
                    };

                    if dy < 2 {
                        top_r += color.0 as u32;
                        top_g += color.1 as u32;
                        top_b += color.2 as u32;
                        top_n += 1;
                    } else {
                        bot_r += color.0 as u32;
                        bot_g += color.1 as u32;
                        bot_b += color.2 as u32;
                        bot_n += 1;
                    }
                }
            }

            let upper = Rgb(
                (top_r / top_n.max(1)) as u8,
                (top_g / top_n.max(1)) as u8,
                (top_b / top_n.max(1)) as u8,
            );
            let lower = Rgb(
                (bot_r / bot_n.max(1)) as u8,
                (bot_g / bot_n.max(1)) as u8,
                (bot_b / bot_n.max(1)) as u8,
            );

            let cell = &mut buf[(area.x + col, area.y + row)];
            cell.set_char('▀');
            cell.set_style(
                Style::default()
                    .fg(Color::Rgb(upper.0, upper.1, upper.2))
                    .bg(Color::Rgb(lower.0, lower.1, lower.2)),
            );
        }
    }
}

const ASCII_RAMP: &[u8] = b" .:-=+*#%@";

/// ASCII blit: 1×2 pixel block per cell, averaged and mapped to a character ramp.
/// Uses same pixel layout as HalfBlock (1 col, 2 rows per cell) for correct aspect ratio.
fn blit_ascii(fb: &Framebuffer, area: Rect, buf: &mut Buffer) {
    for row in 0..area.height {
        for col in 0..area.width {
            let px = col as u32;
            let py_upper = row as u32 * 2;
            let py_lower = py_upper + 1;

            let upper = if px < fb.width && py_upper < fb.height {
                fb.get_pixel(px, py_upper)
            } else {
                Rgb::BLACK
            };
            let lower = if px < fb.width && py_lower < fb.height {
                fb.get_pixel(px, py_lower)
            } else {
                Rgb::BLACK
            };

            let color = Rgb(
                ((upper.0 as u32 + lower.0 as u32) / 2) as u8,
                ((upper.1 as u32 + lower.1 as u32) / 2) as u8,
                ((upper.2 as u32 + lower.2 as u32) / 2) as u8,
            );

            let lum = color.luminance();
            let idx = (lum * (ASCII_RAMP.len() - 1) as f32).round() as usize;
            let ch = ASCII_RAMP[idx.min(ASCII_RAMP.len() - 1)] as char;

            let cell = &mut buf[(area.x + col, area.y + row)];
            cell.set_char(ch);
            cell.set_style(
                Style::default()
                    .fg(Color::Rgb(color.0, color.1, color.2))
                    .bg(Color::Rgb(0, 0, 0)),
            );
        }
    }
}
