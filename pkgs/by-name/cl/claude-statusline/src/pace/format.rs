//! Render a [`Projection`] into a styled [`Segment`].
//!
//! Compact format, glyph-first. The body is the **projected percentage
//! at reset** — a linear function of the rate estimate, so adjacent
//! renders with similar rates produce similar bodies. (The previous
//! "minutes until cap" body had a `1/rate` nonlinearity that made the
//! segment jump around wildly for small real-world rate changes.)
//!
//! | State      | Example     | Meaning                                  |
//! |------------|-------------|------------------------------------------|
//! | Cool       | `❄ → 42%`   | projected to reach 42% by reset         |
//! | On-pace    | `✓ → 97%`   | projected to land near the cap          |
//! | Too hot    | `🔥 → 142%`  | projected to blow past the cap          |
//! | Cold start | `⏳ warming`| too early in the window to project       |
//! | At cap     | `🔥 at cap` | already ≥100%, no runway left            |

use std::time::Duration;

use crate::render::colors::Palette;
use crate::render::format::humanize_duration;
use crate::render::segment::Segment;

use super::glyphs::GlyphSet;
use super::projection::{PaceState, Projection};

/// Displayed projected percentages are clamped to this upper bound so a
/// degenerate short-lookback spike can't blow out the segment width.
pub const MAX_DISPLAYED_PCT: u32 = 999;

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

/// Body text. `at cap` when already saturated. For `TooHot` we append
/// `· cap Xm` (time until 100%) and `· rest Ym` (pause to land safely)
/// when finite — those are the "you should rest" advisory the user
/// asked for. Cool / `OnPace` stay compact.
fn body_text(proj: &Projection) -> String {
    if proj.current_pct >= 100.0 {
        return "at cap".to_string();
    }
    let mut s = format_projected_pct(proj.projected_pct_at_reset);
    if matches!(proj.state, PaceState::TooHot) {
        append_advisory(&mut s, "cap", proj.cap_eta);
        append_advisory(&mut s, "rest", proj.rest_to_safe);
    }
    s
}

fn append_advisory(s: &mut String, label: &str, d: Option<Duration>) {
    if let Some(d) = round_to_min(d) {
        s.push_str(" · ");
        s.push_str(label);
        s.push(' ');
        s.push_str(&humanize_duration(d.as_secs().cast_signed()));
    }
}

/// Round a duration up to the nearest minute, dropping anything below
/// 60s entirely so we never render `cap 0m` / `rest 0m`.
fn round_to_min(d: Option<Duration>) -> Option<Duration> {
    let d = d?;
    let secs = d.as_secs();
    if secs < 60 {
        return None;
    }
    // Round to nearest minute for display.
    let mins = (secs + 30) / 60;
    Some(Duration::from_secs(mins * 60))
}

/// `→ 142%`, `→ 97%`, `→ 9%`. Non-finite / out-of-range values clamp to
/// [`MAX_DISPLAYED_PCT`] so the segment width stays stable.
#[must_use]
pub fn format_projected_pct(pct: f64) -> String {
    if !pct.is_finite() || pct < 0.0 {
        return format!("→ {MAX_DISPLAYED_PCT}%+");
    }
    let rounded = pct.round();
    if rounded >= f64::from(MAX_DISPLAYED_PCT) {
        return format!("→ {MAX_DISPLAYED_PCT}%+");
    }
    format!("→ {}%", rounded as u32)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn projected_pct_formatting() {
        assert_eq!(format_projected_pct(0.0), "→ 0%");
        assert_eq!(format_projected_pct(42.0), "→ 42%");
        assert_eq!(format_projected_pct(97.4), "→ 97%");
        assert_eq!(format_projected_pct(142.6), "→ 143%");
        assert_eq!(format_projected_pct(999.0), "→ 999%+");
        assert_eq!(format_projected_pct(10_000.0), "→ 999%+");
        assert_eq!(format_projected_pct(f64::INFINITY), "→ 999%+");
    }

    fn proj(state: PaceState, projected: f64, current: f64) -> Projection {
        use std::time::Duration;
        Projection {
            state,
            current_pct: current,
            rate_pct_per_min: 0.3,
            fair_share_pct_per_min: 0.5,
            projected_pct_at_reset: projected,
            remaining: Duration::from_secs(2 * 3600),
            cap_eta: None,
            rest_to_safe: None,
        }
    }

    #[test]
    fn body_shows_projected_pct() {
        assert_eq!(body_text(&proj(PaceState::Cool, 42.0, 10.0)), "→ 42%");
        assert_eq!(body_text(&proj(PaceState::OnPace, 97.0, 30.0)), "→ 97%");
        assert_eq!(body_text(&proj(PaceState::TooHot, 142.0, 60.0)), "→ 142%");
    }

    #[test]
    fn body_at_cap_when_over_100() {
        assert_eq!(body_text(&proj(PaceState::TooHot, 150.0, 100.0)), "at cap");
        assert_eq!(body_text(&proj(PaceState::TooHot, 200.0, 105.0)), "at cap");
    }

    #[test]
    fn small_rate_jitter_produces_small_display_jitter() {
        // Regression for the bug: a 1% change in projected pct should
        // produce at most a 1% change in the rendered body. The old
        // delta_to_cap_mins metric would turn this into an hour-scale
        // swing near low rates.
        let a = body_text(&proj(PaceState::Cool, 41.0, 10.0));
        let b = body_text(&proj(PaceState::Cool, 42.0, 10.0));
        assert_eq!(a, "→ 41%");
        assert_eq!(b, "→ 42%");
    }

    fn proj_with_advisory(
        cap_eta: Option<Duration>,
        rest: Option<Duration>,
    ) -> Projection {
        Projection {
            state: PaceState::TooHot,
            current_pct: 60.0,
            rate_pct_per_min: 3.0,
            fair_share_pct_per_min: 1.5,
            projected_pct_at_reset: 142.0,
            remaining: Duration::from_secs(2 * 3600),
            cap_eta,
            rest_to_safe: rest,
        }
    }

    #[test]
    fn hot_body_includes_cap_and_rest_when_finite() {
        let p = proj_with_advisory(
            Some(Duration::from_secs(47 * 60)),
            Some(Duration::from_secs(32 * 60)),
        );
        let body = body_text(&p);
        assert!(body.contains("→ 142%"), "got {body}");
        assert!(body.contains("· cap 47m"), "got {body}");
        assert!(body.contains("· rest 32m"), "got {body}");
    }

    #[test]
    fn hot_body_omits_cap_when_none() {
        let p = proj_with_advisory(None, Some(Duration::from_secs(15 * 60)));
        let body = body_text(&p);
        assert!(!body.contains("cap"), "got {body}");
        assert!(body.contains("· rest 15m"));
    }

    #[test]
    fn hot_body_omits_rest_when_none() {
        let p = proj_with_advisory(Some(Duration::from_secs(20 * 60)), None);
        let body = body_text(&p);
        assert!(body.contains("· cap 20m"));
        assert!(!body.contains("rest"), "got {body}");
    }

    #[test]
    fn sub_minute_advisories_are_dropped() {
        let p = proj_with_advisory(
            Some(Duration::from_secs(30)),
            Some(Duration::from_secs(45)),
        );
        let body = body_text(&p);
        assert_eq!(body, "→ 142%");
    }

    #[test]
    fn cool_body_ignores_advisory_fields() {
        let mut p = proj_with_advisory(
            Some(Duration::from_secs(47 * 60)),
            Some(Duration::from_secs(32 * 60)),
        );
        p.state = PaceState::Cool;
        let body = body_text(&p);
        assert_eq!(body, "→ 142%");
    }

    #[test]
    fn render_compact_hot() {
        use crate::pace::glyphs::EMOJI;
        let p = proj(PaceState::TooHot, 142.0, 60.0);
        let seg = render(&p, &EMOJI, &Palette::dark());
        let mut out = String::new();
        seg.write_to(&mut out);
        assert!(out.contains("🔥"), "missing hot glyph: {out}");
        assert!(out.contains("→ 142%"), "missing projection: {out}");
    }

    #[test]
    fn render_compact_cool() {
        use crate::pace::glyphs::EMOJI;
        let p = proj(PaceState::Cool, 34.0, 12.0);
        let seg = render(&p, &EMOJI, &Palette::dark());
        let mut out = String::new();
        seg.write_to(&mut out);
        assert!(out.contains("❄"));
        assert!(out.contains("→ 34%"));
    }

    #[test]
    fn render_warming_during_cold_start() {
        use crate::pace::glyphs::EMOJI;
        let p = proj(PaceState::ColdStart, 0.0, 2.0);
        let seg = render(&p, &EMOJI, &Palette::dark());
        let mut out = String::new();
        seg.write_to(&mut out);
        assert!(out.contains("warming"), "got: {out}");
    }
}
