//! Classify the current burn rate against the fair-share budget and
//! project where the 5h window will end up at reset.

use std::time::Duration;

use super::ewma::EwmaTracker;
use super::window::Window;
use crate::pace::PaceSettings;

/// Pace classification.
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum PaceState {
    /// Not enough data (or too early in the window) to project.
    ColdStart,
    /// Burning well under fair-share.
    Cool,
    /// Burning close to fair-share — projection lands near 100%.
    OnPace,
    /// Burning above fair-share — projection overruns the window.
    TooHot,
}

/// Everything the format layer needs to render a pace segment.
#[derive(Copy, Clone, Debug)]
pub struct Projection {
    pub state: PaceState,
    pub current_pct: f64,
    pub rate_pct_per_min: f64,
    pub fair_share_pct_per_min: f64,
    /// `current_pct + rate × minutes_remaining`. Finite for display
    /// purposes even when the raw rate would overflow — callers should
    /// format with a reasonable cap.
    pub projected_pct_at_reset: f64,
    pub remaining: Duration,
    /// Minutes between hitting the 100% cap and the window reset.
    /// Positive = runway outlasts the window (safe, "spare"); negative
    /// = you'd hit the cap before reset (hot, "over"). `None` when not
    /// meaningful (zero rate, already at/over cap, ColdStart).
    pub delta_to_cap_mins: Option<f64>,
}

/// Fold the window + current percentage + rolling rate into a
/// classified projection.
#[must_use]
pub fn classify(
    window: &Window,
    current_pct: f64,
    ewma: &EwmaTracker,
    settings: &PaceSettings,
    now: u64,
) -> Projection {
    let remaining = window.remaining(now);
    let remaining_mins = remaining.as_secs() as f64 / 60.0;
    let fair = window.fair_share(current_pct, now);
    let rate = ewma.rate_pct_per_min.max(0.0);
    let projected = (current_pct + rate * remaining_mins).max(current_pct);

    let elapsed_secs = window.elapsed(now).as_secs();
    let warmup_secs = u64::from(settings.warmup_mins) * 60;
    let warming_up = elapsed_secs < warmup_secs || ewma.samples_consumed < 1;

    let state = if warming_up {
        PaceState::ColdStart
    } else if !fair.is_finite() || fair == 0.0 {
        // Edge: no time left, or no headroom left. Treat any non-zero
        // rate as too hot, zero-rate saturation as on-pace.
        if rate > 0.0 {
            PaceState::TooHot
        } else {
            PaceState::OnPace
        }
    } else {
        let ratio = rate / fair;
        if ratio < settings.cool_below {
            PaceState::Cool
        } else if ratio > settings.hot_above {
            PaceState::TooHot
        } else {
            PaceState::OnPace
        }
    };

    // Runway in minutes — how long current rate keeps us below 100%.
    // Zero rate → infinite runway (no meaningful delta to show).
    // Already at/over cap → already zero runway.
    let delta_to_cap_mins = if rate > 0.0 && current_pct < 100.0 {
        let runway = (100.0 - current_pct) / rate;
        Some(runway - remaining_mins)
    } else {
        None
    };

    Projection {
        state,
        current_pct,
        rate_pct_per_min: rate,
        fair_share_pct_per_min: fair,
        projected_pct_at_reset: projected,
        remaining,
        delta_to_cap_mins,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn settings() -> PaceSettings {
        PaceSettings::default()
    }

    fn window_at(now: u64, until: u64) -> Window {
        Window {
            started_at: now.saturating_sub(super::super::window::BLOCK_SECS - (until - now)),
            resets_at: until,
        }
    }

    fn ewma(rate: f64) -> EwmaTracker {
        EwmaTracker {
            alpha: 0.2,
            rate_pct_per_min: rate,
            samples_consumed: 4,
        }
    }

    #[test]
    fn cold_start_when_inside_warmup() {
        let mut s = settings();
        s.warmup_mins = 10;
        let now = 1_000_000;
        let w = Window {
            started_at: now - 60, // one minute in
            resets_at: now - 60 + super::super::window::BLOCK_SECS,
        };
        let p = classify(&w, 5.0, &ewma(0.2), &s, now);
        assert_eq!(p.state, PaceState::ColdStart);
    }

    #[test]
    fn cool_when_rate_below_fair() {
        let now = 1_000_000;
        let w = window_at(now, now + 60 * 60); // 1h left
        // current=10 → headroom 90 over 60min → fair=1.5 %/min.
        // rate 0.5 %/min → ratio 0.33 → cool.
        let p = classify(&w, 10.0, &ewma(0.5), &settings(), now);
        assert_eq!(p.state, PaceState::Cool);
        assert!((p.projected_pct_at_reset - (10.0 + 0.5 * 60.0)).abs() < 1e-6);
    }

    #[test]
    fn too_hot_when_rate_above_fair() {
        let now = 1_000_000;
        let w = window_at(now, now + 60 * 60);
        // fair=1.5 %/min, rate=3 → ratio 2 → hot.
        let p = classify(&w, 10.0, &ewma(3.0), &settings(), now);
        assert_eq!(p.state, PaceState::TooHot);
        assert!(p.projected_pct_at_reset > 100.0);
    }

    #[test]
    fn on_pace_within_corridor() {
        let now = 1_000_000;
        let w = window_at(now, now + 60 * 60); // fair=1.5
        let p = classify(&w, 10.0, &ewma(1.5), &settings(), now);
        assert_eq!(p.state, PaceState::OnPace);
    }

    #[test]
    fn projection_never_decreases() {
        let now = 1_000_000;
        let w = window_at(now, now + 60 * 60);
        let p = classify(&w, 42.0, &ewma(0.0), &settings(), now);
        assert!(p.projected_pct_at_reset >= p.current_pct);
    }
}
