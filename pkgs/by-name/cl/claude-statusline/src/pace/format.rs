//! Render a [`Projection`] into a styled [`Segment`].
//!
//! Compact format, glyph-first:
//!
//! | State      | Example     | Meaning                                  |
//! |------------|-------------|------------------------------------------|
//! | Cool       | `❄ +2h34m`  | runway outlasts window by 2h34m          |
//! | On-pace    | `✓ on track`| runway ≈ window (inside the ±5m deadzone)|
//! | Too hot    | `🔥 −34m`   | you'd hit 100% 34 minutes before reset   |
//! | Cold start | `⏳ warming`| too early in the window to project       |
//!
//! The glyph carries the state; the color underscores it; the sign +
//! number carries magnitude. No `%`, no "spare/over" — the existing
//! `rate_limits` segment already shows the current percentage.

use crate::render::colors::Palette;
use crate::render::segment::Segment;

use super::glyphs::GlyphSet;
use super::projection::{PaceState, Projection};

/// Minutes around zero where we collapse to `on track` so ewma jitter
/// doesn't make the sign flicker frame-to-frame.
pub const ON_TRACK_DEADZONE_MINS: f64 = 5.0;

#[must_use]
pub fn render(proj: &Projection, glyphs: &GlyphSet, pal: &Palette) -> Segment {
    let mut s = Segment::droppable();
    match proj.state {
        PaceState::ColdStart => {
            push_glyph(&mut s, glyphs.cold_start, pal.dim);
            s.push_styled("warming", pal.dim);
        }
        state => {
            let (glyph, style) = match state {
                PaceState::Cool => (glyphs.cool, pal.cyan),
                PaceState::OnPace => (glyphs.on_pace, pal.green),
                PaceState::TooHot => (glyphs.too_hot, pal.red),
                PaceState::ColdStart => unreachable!(),
            };
            push_glyph(&mut s, glyph, style);
            s.push_styled(body_text(proj), style);
        }
    }
    s
}

fn push_glyph(s: &mut Segment, glyph: &str, style: anstyle::Style) {
    if !glyph.is_empty() {
        s.push_styled(format!("{glyph} "), style);
    }
}

/// Render the text following the glyph. `on track` inside the deadzone,
/// signed compact duration otherwise. `at cap` when we've already burned
/// past 100% and no delta is meaningful.
fn body_text(proj: &Projection) -> String {
    let Some(delta) = proj.delta_to_cap_mins else {
        if proj.current_pct >= 100.0 {
            return "at cap".to_string();
        }
        return "on track".to_string();
    };
    if delta.abs() < ON_TRACK_DEADZONE_MINS {
        return "on track".to_string();
    }
    format_signed_mins(delta)
}

/// Compact signed minutes: `+47m`, `−34m`, `+2h34m`. Uses the Unicode
/// minus sign so the negative case lines up visually with the positive
/// plus. Caps absolute magnitude at 99h so a degenerate rate can't blow
/// out the segment width.
#[must_use]
pub fn format_signed_mins(delta_mins: f64) -> String {
    if !delta_mins.is_finite() {
        return if delta_mins > 0.0 {
            "+∞".to_string()
        } else {
            "−∞".to_string()
        };
    }
    let sign = if delta_mins >= 0.0 { '+' } else { '−' };
    let total = delta_mins.abs().round() as u64;
    let capped = total.min(99 * 60 + 59);
    format!("{sign}{}", format_mins(capped))
}

fn format_mins(mins: u64) -> String {
    if mins < 60 {
        format!("{mins}m")
    } else {
        let h = mins / 60;
        let m = mins % 60;
        if m == 0 {
            format!("{h}h")
        } else {
            format!("{h}h{m:02}m")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn signed_mins_formatting() {
        assert_eq!(format_signed_mins(0.0), "+0m");
        assert_eq!(format_signed_mins(47.0), "+47m");
        assert_eq!(format_signed_mins(-34.0), "−34m");
        assert_eq!(format_signed_mins(154.0), "+2h34m");
        assert_eq!(format_signed_mins(-120.0), "−2h");
        assert_eq!(format_signed_mins(f64::INFINITY), "+∞");
    }

    #[test]
    fn extreme_delta_is_capped() {
        let text = format_signed_mins(10_000.0);
        assert_eq!(text, "+99h59m");
    }

    fn proj(state: PaceState, delta: Option<f64>, current: f64) -> Projection {
        use std::time::Duration;
        Projection {
            state,
            current_pct: current,
            rate_pct_per_min: 0.3,
            fair_share_pct_per_min: 0.5,
            projected_pct_at_reset: 80.0,
            remaining: Duration::from_secs(2 * 3600),
            delta_to_cap_mins: delta,
        }
    }

    #[test]
    fn body_collapses_deadzone_to_on_track() {
        assert_eq!(body_text(&proj(PaceState::OnPace, Some(2.0), 47.0)), "on track");
        assert_eq!(body_text(&proj(PaceState::OnPace, Some(-3.5), 47.0)), "on track");
    }

    #[test]
    fn body_shows_signed_delta_outside_deadzone() {
        assert_eq!(body_text(&proj(PaceState::Cool, Some(47.0), 10.0)), "+47m");
        assert_eq!(body_text(&proj(PaceState::TooHot, Some(-34.0), 60.0)), "−34m");
    }

    #[test]
    fn body_at_cap_when_over_100() {
        assert_eq!(body_text(&proj(PaceState::TooHot, None, 100.0)), "at cap");
        assert_eq!(body_text(&proj(PaceState::TooHot, None, 105.0)), "at cap");
    }

    #[test]
    fn body_zero_rate_is_on_track() {
        // rate = 0 → projection.delta is None → on track.
        assert_eq!(body_text(&proj(PaceState::OnPace, None, 47.0)), "on track");
    }

    #[test]
    fn render_compact_hot() {
        use crate::pace::glyphs::EMOJI;
        use crate::render::colors::Palette;
        let p = proj(PaceState::TooHot, Some(-34.0), 60.0);
        let seg = render(&p, &EMOJI, &Palette::dark());
        let mut out = String::new();
        seg.write_to(&mut out);
        assert!(out.contains("🔥"), "missing hot glyph: {out}");
        assert!(out.contains("−34m"), "missing delta: {out}");
        assert!(!out.contains("by reset"), "old verbose text present: {out}");
    }

    #[test]
    fn render_compact_cool() {
        use crate::pace::glyphs::EMOJI;
        use crate::render::colors::Palette;
        let p = proj(PaceState::Cool, Some(154.0), 12.0);
        let seg = render(&p, &EMOJI, &Palette::dark());
        let mut out = String::new();
        seg.write_to(&mut out);
        assert!(out.contains("❄"));
        assert!(out.contains("+2h34m"));
    }

    #[test]
    fn render_on_track_within_deadzone() {
        use crate::pace::glyphs::EMOJI;
        use crate::render::colors::Palette;
        let p = proj(PaceState::OnPace, Some(2.0), 30.0);
        let seg = render(&p, &EMOJI, &Palette::dark());
        let mut out = String::new();
        seg.write_to(&mut out);
        assert!(out.contains("on track"), "got: {out}");
    }
}
