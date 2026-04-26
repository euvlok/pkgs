//! Drop-to-fit algorithms for multi-line segment layouts.
//!
//! Given a set of lines (each a `Vec<Segment>`), these functions remove
//! droppable segments from the right until every line fits within the
//! terminal width. Two strategies are provided:
//!
//! - [`fit_with_alignment`]: accounts for cross-line column padding so that a
//!   wide segment in line A doesn't silently overflow line B.
//! - [`fit_unaligned`]: budgets each line independently on its raw width, used by
//!   `--no-align`.

use crate::render::segment::{Segment, SegmentKind};

/// Index of the rightmost droppable segment in `line`, or `None` if the
/// line has nothing left to give up. Anchors are skipped by construction.
fn rightmost_droppable(line: &[Segment]) -> Option<usize> {
    line.iter()
        .rposition(|s| s.kind == SegmentKind::Droppable)
}

/// Index of the rightmost segment that still has a compact form to fall
/// back to. Anchors with a compact form are eligible too — they're not
/// dropped, but they can shrink. Borrowed from the i3bar `short_text`
/// pattern: prefer losing detail over losing the whole segment.
fn rightmost_compactable(line: &[Segment]) -> Option<usize> {
    line.iter().rposition(Segment::has_compact)
}

/// Drop segments across all lines until every line fits in `max_cols`,
/// returning the final per-column widths so callers don't have to
/// recompute them.
///
/// Accounts for the padding alignment will add. Each iteration finds
/// the worst-overflowing line, drops one droppable segment from its
/// right, then recomputes column widths - that lets a drop in line A
/// shrink a column and rescue line B too. Anchor segments (the first
/// of each line) are never dropped; if the worst line has nothing left
/// to drop we bail to avoid an infinite loop.
pub fn fit_with_alignment(
    lines: &mut [Vec<Segment>],
    sep_width: usize,
    max_cols: Option<usize>,
) -> Vec<usize> {
    let Some(max) = max_cols else {
        return column_widths(lines);
    };
    loop {
        let widths = column_widths(lines);
        let worst = lines
            .iter()
            .enumerate()
            .map(|(i, line)| (i, aligned_width(line, &widths, sep_width)))
            .filter(|(_, w)| *w > max)
            .max_by_key(|(_, w)| *w);
        let Some((i, _)) = worst else {
            return widths;
        };
        if let Some(j) = rightmost_compactable(&lines[i]) {
            lines[i][j].apply_compact();
            continue;
        }
        match rightmost_droppable(&lines[i]) {
            Some(j) => {
                lines[i].remove(j);
            }
            None => return widths,
        }
    }
}

/// Drop-to-fit without column alignment.
///
/// Each line is budgeted on its own raw width (segments + separators).
/// Only used by `--no-align`, which trades cross-line tidiness for
/// shorter lines on narrow terminals.
pub fn fit_unaligned(lines: &mut [Vec<Segment>], sep_width: usize, max_cols: Option<usize>) {
    let Some(max) = max_cols else {
        return;
    };
    for line in lines.iter_mut() {
        loop {
            let raw: usize = line.iter().map(Segment::width).sum::<usize>()
                + sep_width * line.len().saturating_sub(1);
            if raw <= max {
                break;
            }
            if let Some(j) = rightmost_compactable(line) {
                line[j].apply_compact();
                continue;
            }
            match rightmost_droppable(line) {
                Some(j) => {
                    line.remove(j);
                }
                None => break,
            }
        }
    }
}

/// Width a line will occupy *after* per-column padding is applied. We
/// charge each non-final segment its column's full width, since that's
/// what `write_line` will pad it to.
#[must_use]
pub fn aligned_width(line: &[Segment], col_widths: &[usize], sep_width: usize) -> usize {
    if line.is_empty() {
        return 0;
    }
    let last = line.len() - 1;
    let cells: usize = line
        .iter()
        .enumerate()
        .map(|(i, seg)| {
            if i == last {
                seg.width()
            } else {
                col_widths.get(i).copied().unwrap_or(0)
            }
        })
        .sum();
    cells + sep_width * last
}

/// Compute the maximum width seen at each column index across every line.
///
/// Lines with fewer segments simply contribute nothing past their
/// own length, which is the right behavior - we don't want to extend a
/// short line's last column with phantom padding.
#[must_use]
pub fn column_widths(lines: &[Vec<Segment>]) -> Vec<usize> {
    let max_cols = lines.iter().map(Vec::len).max().unwrap_or(0);
    (0..max_cols)
        .map(|col| {
            lines
                .iter()
                .filter_map(|line| line.get(col))
                .map(Segment::width)
                .max()
                .unwrap_or(0)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::render::segment::Segment;

    fn anchor(text: &str) -> Segment {
        let mut s = Segment::anchor();
        s.push_plain(text.to_string());
        s
    }

    fn droppable_with_compact(full: &str, compact: &str) -> Segment {
        use crate::render::segment::Cell;
        let mut s = Segment::droppable();
        s.push_plain(full.to_string());
        s.set_compact(vec![Cell::plain(compact.to_string())]);
        s
    }

    #[test]
    fn compact_swap_runs_before_drop() {
        // Anchor (4) + sep (3) + full (10) = 17. Budget 12 forces fit;
        // compact form is 4 wide, total becomes 11 — fits without
        // dropping.
        let mut lines = vec![vec![anchor("home"), droppable_with_compact("longvalue!", "v=1")]];
        fit_unaligned(&mut lines, 3, Some(12));
        assert_eq!(lines[0].len(), 2, "compact should fit, not be dropped");
        assert_eq!(lines[0][1].width(), 3);
        assert!(!lines[0][1].has_compact(), "compact consumed");
    }

    #[test]
    fn drop_when_compact_still_too_wide() {
        // Even compact (8) plus anchor (4) plus sep (3) = 15; budget 10
        // forces a drop after the compact swap.
        let mut lines = vec![vec![
            anchor("home"),
            droppable_with_compact("really-long-value", "stillbig"),
        ]];
        fit_unaligned(&mut lines, 3, Some(10));
        assert_eq!(lines[0].len(), 1, "no fit even after compact → drop");
    }
}
