//! Keeps a local terminal's cell pixel size current after the font
//! changes (ctrl +/-) without asking the terminal again.
//!
//! The startup probe (`image_probe_terminal`) gets the exact cell size
//! from the terminal's reply to `CSI 16 t`. Asking again mid-session
//! would mean reading stdin next to crossterm's event reader, and
//! crossterm discards that reply, so the size is worked out from the
//! OS window size instead (`TIOCGWINSZ`, an ioctl, no terminal I/O).
//!
//! That window size is the whole window, padding included, so
//! `pixels / cells` overshoots by up to a cell's worth of leftover
//! pixels. The terminal lays out `cells = floor((pixels - padding) /
//! cell)`, and at the probe we know the cell exactly, which bounds the
//! padding. After a change, the cell is the smallest whole length that
//! still fits the new grid under that bound. When it's off, it's off
//! small: an image ends up a hair smaller rather than spilling into the
//! next row.

/// A window's grid and its size in pixels, as the OS reports them.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WindowDims {
    pub cols: u16,
    pub rows: u16,
    pub width_px: u16,
    pub height_px: u16,
}

impl WindowDims {
    fn usable(&self) -> bool {
        self.cols > 0 && self.rows > 0 && self.width_px > 0 && self.height_px > 0
    }
}

/// Follows the window from the size it had at the probe.
#[derive(Debug)]
pub struct CellTracker {
    pad_max: (u16, u16),
    window: WindowDims,
}

impl CellTracker {
    /// Starts from the window at the probe and the cell size the probe
    /// found. `None` when the OS reports no pixel size, which leaves the
    /// probe's cell size in place for good.
    pub fn new(window: WindowDims, cell: (u16, u16)) -> Option<Self> {
        if !window.usable() || cell.0 == 0 || cell.1 == 0 {
            return None;
        }

        let pad = |px: u16, cells: u16, len: u16| {
            (px as u32).saturating_sub(cells as u32 * len as u32) as u16
        };

        Some(Self {
            pad_max: (
                pad(window.width_px, window.cols, cell.0),
                pad(window.height_px, window.rows, cell.1),
            ),
            window,
        })
    }

    /// The new cell size when the window changed since the last call,
    /// `None` when it didn't (or the OS reports nothing usable).
    pub fn update(&mut self, window: WindowDims) -> Option<(u16, u16)> {
        if window == self.window || !window.usable() {
            return None;
        }

        self.window = window;

        Some((
            cell_len(window.width_px, window.cols, self.pad_max.0),
            cell_len(window.height_px, window.rows, self.pad_max.1),
        ))
    }
}

/// The smallest whole cell length `len` with `cells = floor((px - pad)
/// / len)` for some padding `pad <= pad_max`, capped at `px / cells`.
fn cell_len(px: u16, cells: u16, pad_max: u16) -> u16 {
    let (px, cells) = (px as u32, cells as u32);
    let upper = (px / cells).max(1);
    let lower = px.saturating_sub(pad_max as u32) / (cells + 1) + 1;
    lower.min(upper) as u16
}

#[cfg(test)]
mod tests {
    use super::*;

    // Measured in Ghostty on a 1916x998 px window: the grid and the cell
    // size the terminal reported (`CSI 16 t`) at three font sizes.
    fn window(cols: u16, rows: u16) -> WindowDims {
        WindowDims {
            cols,
            rows,
            width_px: 1916,
            height_px: 998,
        }
    }

    #[test]
    fn follows_the_font_through_ctrl_plus_and_back() {
        let mut tracker = CellTracker::new(window(191, 47), (10, 21)).unwrap();

        assert_eq!(tracker.update(window(119, 27)), Some((16, 36)));
        assert_eq!(tracker.update(window(87, 20)), Some((22, 48)));
        assert_eq!(tracker.update(window(191, 47)), Some((10, 21)));
    }

    #[test]
    fn an_unchanged_window_keeps_the_cell_size() {
        let mut tracker = CellTracker::new(window(191, 47), (10, 21)).unwrap();
        assert_eq!(tracker.update(window(191, 47)), None);
    }

    #[test]
    fn no_pixel_size_from_the_os_means_no_tracking() {
        let no_pixels = WindowDims {
            cols: 80,
            rows: 24,
            width_px: 0,
            height_px: 0,
        };

        assert!(CellTracker::new(no_pixels, (10, 20)).is_none());

        let mut tracker = CellTracker::new(window(191, 47), (10, 21)).unwrap();
        assert_eq!(tracker.update(no_pixels), None);
    }

    #[test]
    fn a_resized_window_at_the_same_font_keeps_the_cell_size() {
        let mut tracker = CellTracker::new(window(191, 47), (10, 21)).unwrap();

        // Half the width, same font: 95 columns of 10 px plus padding.
        let narrower = WindowDims {
            cols: 95,
            rows: 47,
            width_px: 958,
            height_px: 998,
        };

        assert_eq!(tracker.update(narrower), Some((10, 21)));
    }

    #[test]
    fn cell_len_never_exceeds_pixels_per_cell() {
        // No room for the padding bound to matter: the cap wins.
        assert_eq!(cell_len(100, 10, 0), 10);
        assert_eq!(cell_len(5, 10, 0), 1);
    }
}
