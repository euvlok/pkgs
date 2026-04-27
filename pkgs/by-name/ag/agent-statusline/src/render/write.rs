//! Line serialization: separator construction and final ANSI output.
//!
//! This module owns the last mile of rendering: given a list of
//! [`Segment`]s, a separator, and column widths, it writes the padded,
//! styled output into a `String`.

use crate::render::colors::Palette;
use crate::render::segment::{Cell, Segment};

/// Pre-built separator: ` <DIM>│</DIM> ` as a structured cell list so
/// the renderer doesn't need to know how to style it.
pub(super) struct Sep {
    pub cells: Vec<Cell>,
    pub width: usize,
}

pub(super) fn build_separator(glyph: &str, pal: &Palette) -> Sep {
    let cells = vec![Cell::new(glyph.to_string(), pal.dim)];
    let width = cells.iter().map(Cell::width).sum();
    Sep { cells, width }
}

pub(super) fn write_line(out: &mut String, segments: &[Segment], sep: &Sep, col_widths: &[usize]) {
    let last = segments.len().saturating_sub(1);
    for (i, seg) in segments.iter().enumerate() {
        seg.write_to(out);
        if i == last {
            continue;
        }
        let pad = col_widths
            .get(i)
            .copied()
            .unwrap_or(0)
            .saturating_sub(seg.width());
        out.extend(std::iter::repeat_n(' ', pad));
        for cell in &sep.cells {
            cell.write_to(out);
        }
    }
}

pub(super) fn plain_line(segments: &[Segment], sep: &Sep, col_widths: &[usize]) -> String {
    let mut out = String::new();
    let last = segments.len().saturating_sub(1);
    for (i, seg) in segments.iter().enumerate() {
        out.push_str(&seg.plain_text());
        if i == last {
            continue;
        }
        let pad = col_widths
            .get(i)
            .copied()
            .unwrap_or(0)
            .saturating_sub(seg.width());
        out.extend(std::iter::repeat_n(' ', pad));
        for cell in &sep.cells {
            out.push_str(&cell.text);
        }
    }
    out
}
