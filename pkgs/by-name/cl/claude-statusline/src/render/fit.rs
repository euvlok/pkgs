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
    line.iter().rposition(|s| s.kind == SegmentKind::Droppable)
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
/// Accounts for the padding alignment will add. Each iteration evaluates the
/// whole layout, not just the currently overflowing line: a wide segment in
/// line A can define a shared column width that makes line B overflow, so
/// compacting/dropping line A may preserve more information than dropping line
/// B's own rightmost segment. Anchor segments (the first of each line) are
/// never dropped; if no candidate can improve the overflow, we bail.
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
        let Some(score) = overflow_score(lines, sep_width, max) else {
            return widths;
        };
        if let Some((line, col)) = best_compaction(lines, sep_width, max, score) {
            lines[line][col].apply_compact();
            continue;
        }
        if let Some((line, col)) = best_drop(lines, sep_width, max, score) {
            lines[line].remove(col);
            continue;
        }
        return widths;
    }
}

#[derive(Copy, Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
struct OverflowScore {
    max: usize,
    total: usize,
}

fn overflow_score(
    lines: &[Vec<Segment>],
    sep_width: usize,
    max_cols: usize,
) -> Option<OverflowScore> {
    let widths = column_widths(lines);
    let mut score = OverflowScore { max: 0, total: 0 };
    for line in lines {
        let overflow = aligned_width(line, &widths, sep_width).saturating_sub(max_cols);
        score.max = score.max.max(overflow);
        score.total += overflow;
    }
    (score.max > 0).then_some(score)
}

fn best_compaction(
    lines: &[Vec<Segment>],
    sep_width: usize,
    max_cols: usize,
    current: OverflowScore,
) -> Option<(usize, usize)> {
    best_candidate(
        lines,
        sep_width,
        max_cols,
        current,
        |candidate, line, col| candidate[line][col].apply_compact(),
    )
}

fn best_drop(
    lines: &[Vec<Segment>],
    sep_width: usize,
    max_cols: usize,
    current: OverflowScore,
) -> Option<(usize, usize)> {
    best_candidate(
        lines,
        sep_width,
        max_cols,
        current,
        |candidate, line, col| {
            if Some(col) != rightmost_droppable(&candidate[line]) {
                return false;
            }
            candidate[line].remove(col);
            true
        },
    )
}

fn best_candidate(
    lines: &[Vec<Segment>],
    sep_width: usize,
    max_cols: usize,
    current: OverflowScore,
    mut apply: impl FnMut(&mut Vec<Vec<Segment>>, usize, usize) -> bool,
) -> Option<(usize, usize)> {
    let mut best: Option<((usize, usize), OverflowScore)> = None;
    for (line_idx, line) in lines.iter().enumerate() {
        for col_idx in (0..line.len()).rev() {
            let mut candidate = lines.to_vec();
            if !apply(&mut candidate, line_idx, col_idx) {
                continue;
            }
            let score = overflow_score(&candidate, sep_width, max_cols)
                .unwrap_or(OverflowScore { max: 0, total: 0 });
            if score >= current {
                continue;
            }
            if best.is_none_or(|(_, best_score)| score < best_score) {
                best = Some(((line_idx, col_idx), score));
            }
        }
    }
    best.map(|(pos, _)| pos)
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
        Segment::anchor().plain(text.to_string())
    }

    fn droppable(text: &str) -> Segment {
        Segment::droppable().plain(text.to_string())
    }

    fn droppable_with_compact(full: &str, compact: &str) -> Segment {
        use crate::render::segment::Cell;
        Segment::droppable()
            .plain(full.to_string())
            .with_compact(vec![Cell::plain(compact.to_string())])
    }

    fn anchor_with_compact(full: &str, compact: &str) -> Segment {
        use crate::render::segment::Cell;
        Segment::anchor()
            .plain(full.to_string())
            .with_compact(vec![Cell::plain(compact.to_string())])
    }

    #[test]
    fn compact_swap_runs_before_drop() {
        // Anchor (4) + sep (3) + full (10) = 17. Budget 12 forces fit;
        // compact form is 4 wide, total becomes 11 — fits without
        // dropping.
        let mut lines = vec![vec![
            anchor("home"),
            droppable_with_compact("longvalue!", "v=1"),
        ]];
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

    #[test]
    fn aligned_fit_compacts_shared_column_in_other_line_before_dropping() {
        // Line 0 fits by itself (width 10), but its wide first column makes line
        // 1 render as 10 + sep + 4 = 17. Compacting line 0's anchor shrinks the
        // shared column and preserves line 1's droppable `keep` segment.
        let mut lines = vec![
            vec![anchor_with_compact("toolongcol", "x")],
            vec![anchor("b"), droppable("keep")],
        ];
        let widths = fit_with_alignment(&mut lines, 3, Some(10));
        assert_eq!(lines[0][0].width(), 1, "shared column should compact");
        assert_eq!(lines[1].len(), 2, "line 1 segment should be preserved");
        assert_eq!(aligned_width(&lines[1], &widths, 3), 8);
    }
}
