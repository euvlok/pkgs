//! Pacing / burn-rate segment.
//!
//! Treats `rate_limits.five_hour.used_percentage` from stdin as the
//! authoritative current consumption and fits a trailing-window linear
//! regression over a small on-disk ring of `(timestamp, used_pct)`
//! observations to get `%/min`. The resulting projection — *where will
//! the window land at reset?* — is rendered next to `clock` in the
//! layout.
//!
//! Design doc: `PACING_DESIGN.md`.

pub mod format;
pub mod glyphs;
pub mod projection;
pub mod rate;
pub mod ring;
pub mod window;

use std::time::{SystemTime, UNIX_EPOCH};

use crate::input::Input;
use crate::render::colors::Palette;
use crate::render::segment::Segment;

pub use glyphs::{GlyphSet, PaceGlyphs};
pub use projection::{PaceState, Projection};
pub use ring::PctSample;
pub use window::Window;

/// Tunable knobs for the pace segment. All knobs have ship-able defaults
/// and none of them derive from model / tier / plan — see design §1.
#[derive(Copy, Clone, Debug)]
pub struct PaceSettings {
    /// Trailing wall-clock window (minutes) over which the rate is fit.
    /// Shorter = more reactive, longer = more stable. `20` is the ship
    /// default — it filters one-off idle or burst renders while still
    /// reacting inside a single 5h block.
    pub lookback_mins: u32,
    /// `rate/fair < cool_below` → [`PaceState::Cool`].
    pub cool_below: f64,
    /// `rate/fair > hot_above` → [`PaceState::TooHot`].
    pub hot_above: f64,
    /// Wall-clock minutes at the start of a window during which we
    /// suppress the projection — the rate estimate is not yet trustworthy.
    pub warmup_mins: u32,
    /// Which glyph family to render.
    pub glyphs: PaceGlyphs,
    /// Emit `--pace-debug` style output to stderr on every render.
    pub debug: bool,
}

impl Default for PaceSettings {
    fn default() -> Self {
        Self {
            lookback_mins: 20,
            cool_below: 0.9,
            hot_above: 1.2,
            warmup_mins: 10,
            glyphs: PaceGlyphs::Auto,
            debug: false,
        }
    }
}

/// Hot-path entry point for the pace segment.
///
/// `None` means "no pace data" (missing `used_percentage` on stdin,
/// missing `resets_at`, etc.) — the layout elides the segment the same
/// way it does for `cost` when the transcript isn't available.
pub fn pace(input: &Input, settings: &PaceSettings, pal: &Palette, now: u64) -> Option<Segment> {
    let rl = &input.rate_limits.five_hour;
    let current_pct = rl.used_percentage?;
    if !current_pct.is_finite() || current_pct < 0.0 {
        return None;
    }

    let window = Window::from_rate_limit(rl, now)?;
    let projection = compute(&window, current_pct, settings, now);

    if settings.debug {
        emit_debug(&window, &projection);
    }

    let glyphs = settings.glyphs.resolve();
    Some(format::render(&projection, glyphs, pal))
}

/// Load the ring, fold in the current observation + an optional
/// idle-synthesis sample, persist, and classify. Separated from
/// [`pace`] so tests can drive the math without touching stdin.
pub(crate) fn compute(
    window: &Window,
    current_pct: f64,
    settings: &PaceSettings,
    now: u64,
) -> Projection {
    let mut samples = ring::load_ring();
    samples.retain(|s| s.ts_unix >= window.started_at && s.ts_unix < now);
    samples.push(PctSample {
        ts_unix: now,
        used_pct: current_pct,
    });
    ring::persist_ring(&samples);

    let estimate = rate::RateEstimate::from_samples(&samples, settings.lookback_mins, now);
    projection::classify(window, current_pct, &estimate, settings, now)
}

/// Wall-clock "now" in unix seconds. Mirrors the helper in `session.rs`
/// but lives here so the pace hot path has no dependency on session
/// state.
#[must_use]
pub fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn emit_debug(window: &Window, projection: &Projection) {
    use std::fmt::Write as _;
    let mut buf = String::new();
    let _ = writeln!(
        buf,
        "pace: window started_at={} resets_at={} remaining_secs={}",
        window.started_at,
        window.resets_at,
        projection.remaining.as_secs(),
    );
    let _ = writeln!(
        buf,
        "pace: current_pct={:.2} rate={:.3} %/min fair_share={:.3} %/min projected={:.1}% state={:?}",
        projection.current_pct,
        projection.rate_pct_per_min,
        projection.fair_share_pct_per_min,
        projection.projected_pct_at_reset,
        projection.state,
    );
    eprint!("{buf}");

    if let Ok(val) = std::env::var("CLAUDE_STATUSLINE_PACE_DEBUG")
        && !val.is_empty()
        && val != "0"
        && let Some(mut path) = dirs::state_dir().or_else(dirs::cache_dir)
    {
        path.push("claude-statusline");
        if std::fs::create_dir_all(&path).is_ok() {
            path.push("pace-debug.log");
            if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&path) {
                use std::io::Write as _;
                let _ = f.write_all(buf.as_bytes());
            }
        }
    }
}
