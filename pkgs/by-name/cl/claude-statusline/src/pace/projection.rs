//! Classify the current burn rate against the fair-share budget and
//! project where the 5h window will end up at reset.
//!
//! The displayed value is the **projected percentage at reset** — not a
//! "minutes until cap" delta. Projected % is linear in the rate
//! estimate, so small rate wiggles produce small display wiggles.
//! Runway-style `(100 − pct)/rate − remaining` has a `1/rate²`
//! sensitivity that made the segment snap between `−2h` and `−1h`
//! across adjacent renders with only a tiny real change in burn.

use std::time::Duration;

use super::rate::RateEstimate;
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
    /// Time until `used_pct` is projected to hit 100% at the current
    /// rate. `None` when the rate is zero, the user is already capped,
    /// or the cap is past the reset (i.e. the projection lands ≤ 100%).
    pub cap_eta: Option<Duration>,
    /// How long to pause so the rate × remaining-time leaves us at
    /// ≤100% by reset. `None` outside [`PaceState::TooHot`] or when no
    /// rest is needed. Clamped to `[0, remaining]`.
    pub rest_to_safe: Option<Duration>,
}

/// Fold the window + current percentage + rolling rate into a
/// classified projection.
#[must_use]
pub fn classify(
    window: &Window,
    current_pct: f64,
    estimate: &RateEstimate,
    settings: &PaceSettings,
    now: u64,
) -> Projection {
    let remaining = window.remaining(now);
    let remaining_mins = remaining.as_secs() as f64 / 60.0;
    let fair = window.fair_share(current_pct, now);
    let rate = estimate.rate_pct_per_min.max(0.0);
    let projected = (current_pct + rate * remaining_mins).max(current_pct);

    let elapsed_secs = window.elapsed(now).as_secs();
    let warmup_secs = u64::from(settings.warmup_mins) * 60;
    let warming_up = elapsed_secs < warmup_secs || estimate.samples_consumed < 2;

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

    let headroom = (100.0 - current_pct).max(0.0);
    let cap_eta = if rate > 0.0 && headroom > 0.0 {
        let secs = (headroom / rate) * 60.0;
        if secs.is_finite() && secs > 0.0 && secs < remaining.as_secs_f64() {
            Some(Duration::from_secs_f64(secs))
        } else {
            None
        }
    } else {
        None
    };

    // Rest-to-safe: pause Δ minutes so resuming at the same rate over
    // the remaining (rem_mins − Δ) minutes lands at 100%.
    //   current + rate · (rem_mins − Δ) = 100
    //   Δ = rem_mins − headroom / rate
    let rest_to_safe = if matches!(state, PaceState::TooHot) && rate > 0.0 {
        let rest_mins = remaining_mins - headroom / rate;
        if rest_mins.is_finite() && rest_mins > 0.0 {
            let secs = (rest_mins * 60.0).min(remaining.as_secs_f64());
            Some(Duration::from_secs_f64(secs))
        } else {
            None
        }
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
        cap_eta,
        rest_to_safe,
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

    fn estimate(rate: f64) -> RateEstimate {
        RateEstimate {
            rate_pct_per_min: rate,
            samples_consumed: 4,
            span_mins: 20.0,
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
        let p = classify(&w, 5.0, &estimate(0.2), &s, now);
        assert_eq!(p.state, PaceState::ColdStart);
    }

    #[test]
    fn cold_start_when_no_samples() {
        let mut s = settings();
        s.warmup_mins = 0;
        let now = 1_000_000;
        let w = window_at(now, now + 60 * 60);
        let empty = RateEstimate::empty();
        let p = classify(&w, 10.0, &empty, &s, now);
        assert_eq!(p.state, PaceState::ColdStart);
    }

    #[test]
    fn cool_when_rate_below_fair() {
        let now = 1_000_000;
        let w = window_at(now, now + 60 * 60); // 1h left
        // current=10 → headroom 90 over 60min → fair=1.5 %/min.
        // rate 0.5 %/min → ratio 0.33 → cool.
        let p = classify(&w, 10.0, &estimate(0.5), &settings(), now);
        assert_eq!(p.state, PaceState::Cool);
        assert!((p.projected_pct_at_reset - (10.0 + 0.5 * 60.0)).abs() < 1e-6);
    }

    #[test]
    fn too_hot_when_rate_above_fair() {
        let now = 1_000_000;
        let w = window_at(now, now + 60 * 60);
        // fair=1.5 %/min, rate=3 → ratio 2 → hot.
        let p = classify(&w, 10.0, &estimate(3.0), &settings(), now);
        assert_eq!(p.state, PaceState::TooHot);
        assert!(p.projected_pct_at_reset > 100.0);
    }

    #[test]
    fn on_pace_within_corridor() {
        let now = 1_000_000;
        let w = window_at(now, now + 60 * 60); // fair=1.5
        let p = classify(&w, 10.0, &estimate(1.5), &settings(), now);
        assert_eq!(p.state, PaceState::OnPace);
    }

    #[test]
    fn cap_eta_correct_when_hot() {
        let now = 1_000_000;
        let w = window_at(now, now + 60 * 60); // 1h left, fair=1.5
        // current=10, rate=3 → cap in (90/3) min = 30 min.
        let p = classify(&w, 10.0, &estimate(3.0), &settings(), now);
        let eta = p.cap_eta.expect("expected cap_eta");
        assert!(
            (eta.as_secs_f64() - 30.0 * 60.0).abs() < 1.0,
            "got {:?}",
            eta
        );
    }

    #[test]
    fn cap_eta_none_when_under_pace() {
        let now = 1_000_000;
        let w = window_at(now, now + 60 * 60); // fair=1.5
        // rate=0.5 → projected ~40% < 100, so cap is past reset.
        let p = classify(&w, 10.0, &estimate(0.5), &settings(), now);
        assert!(p.cap_eta.is_none());
    }

    #[test]
    fn cap_eta_none_when_already_capped() {
        let now = 1_000_000;
        let w = window_at(now, now + 60 * 60);
        let p = classify(&w, 100.0, &estimate(3.0), &settings(), now);
        assert!(p.cap_eta.is_none());
    }

    #[test]
    fn rest_to_safe_when_hot() {
        let now = 1_000_000;
        let w = window_at(now, now + 60 * 60); // 60 min left
        // current=10, rate=3 → headroom=90, would burn 180 in 60min.
        // Δ = 60 − 90/3 = 30 min.
        let p = classify(&w, 10.0, &estimate(3.0), &settings(), now);
        let rest = p.rest_to_safe.expect("expected rest_to_safe");
        assert!(
            (rest.as_secs_f64() - 30.0 * 60.0).abs() < 1.0,
            "got {:?}",
            rest
        );
    }

    #[test]
    fn rest_to_safe_none_when_cool() {
        let now = 1_000_000;
        let w = window_at(now, now + 60 * 60);
        let p = classify(&w, 10.0, &estimate(0.5), &settings(), now);
        assert!(p.rest_to_safe.is_none());
    }

    #[test]
    fn realistic_hot_scenario_round_trip() {
        // User is 50% used with 2h to reset, burning 0.83%/min (a fast
        // but plausible session). Verify that pausing for `rest_to_safe`
        // and resuming at the same rate lands at exactly 100%.
        let now = 1_000_000;
        let w = window_at(now, now + 2 * 3600);
        let p = classify(&w, 50.0, &estimate(0.83), &settings(), now);

        assert_eq!(p.state, PaceState::TooHot);

        // Cap-ETA: 50 / 0.83 ≈ 60.2 min.
        let eta_min = p.cap_eta.expect("cap_eta").as_secs_f64() / 60.0;
        assert!((eta_min - 60.24).abs() < 0.5, "cap_eta = {eta_min} min");

        // Rest: 120 − 60.24 ≈ 59.76 min.
        let rest_min = p.rest_to_safe.expect("rest_to_safe").as_secs_f64() / 60.0;
        assert!((rest_min - 59.76).abs() < 0.5, "rest = {rest_min} min");

        // Round-trip: pause `rest`, burn at the same rate for what's left.
        let burn_mins = 120.0 - rest_min;
        let final_pct = p.current_pct + p.rate_pct_per_min * burn_mins;
        assert!(
            (final_pct - 100.0).abs() < 0.5,
            "final pct after rest = {final_pct}, expected ~100"
        );
    }

    #[test]
    fn rest_to_safe_clamped_to_remaining() {
        let now = 1_000_000;
        let w = window_at(now, now + 60 * 60); // 60 min left
        // Wildly hot rate → required rest exceeds remaining; clamp.
        let p = classify(&w, 10.0, &estimate(100.0), &settings(), now);
        let rest = p.rest_to_safe.expect("expected rest_to_safe");
        assert!(rest.as_secs() <= 60 * 60);
    }

    #[test]
    fn projection_never_decreases() {
        let now = 1_000_000;
        let w = window_at(now, now + 60 * 60);
        let p = classify(&w, 42.0, &estimate(0.0), &settings(), now);
        assert!(p.projected_pct_at_reset >= p.current_pct);
    }
}
