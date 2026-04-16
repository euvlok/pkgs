//! 5-hour window boundary math.
//!
//! Anthropic's rate-limit payload carries `resets_at` as the authoritative
//! end of the current block. We treat `[resets_at - 5h, resets_at]` as the
//! window: everything is in wall-clock seconds relative to that span.

use std::time::Duration;

use crate::input::RateLimit;

/// One 5-hour rate-limit block.
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub struct Window {
    pub started_at: u64,
    pub resets_at: u64,
}

/// Width of a single block in seconds.
pub const BLOCK_SECS: u64 = 5 * 3600;

impl Window {
    /// Build a window from the stdin payload. Returns `None` when
    /// `resets_at` is missing or in the past.
    #[must_use]
    pub fn from_rate_limit(rl: &RateLimit, now: u64) -> Option<Self> {
        let resets_at_i = rl.resets_at?;
        if resets_at_i <= 0 {
            return None;
        }
        let resets_at = resets_at_i as u64;
        if resets_at <= now {
            return None;
        }
        let started_at = resets_at.saturating_sub(BLOCK_SECS);
        Some(Self {
            started_at,
            resets_at,
        })
    }

    /// Seconds elapsed inside the window. Clamped so callers before the
    /// window's start still get a non-negative value.
    #[must_use]
    pub const fn elapsed(&self, now: u64) -> Duration {
        Duration::from_secs(now.saturating_sub(self.started_at))
    }

    /// Seconds left until reset. Zero once `now >= resets_at`.
    #[must_use]
    pub const fn remaining(&self, now: u64) -> Duration {
        Duration::from_secs(self.resets_at.saturating_sub(now))
    }

    /// Remaining time in minutes, as a float (useful for fair-share math).
    #[must_use]
    pub fn remaining_mins(&self, now: u64) -> f64 {
        self.remaining(now).as_secs() as f64 / 60.0
    }

    /// `%/min` you could spend and exactly hit 100% at reset. Returns
    /// `f64::INFINITY` when no time remains (degenerate boundary), and 0
    /// when the window is already saturated.
    #[must_use]
    pub fn fair_share(&self, current_pct: f64, now: u64) -> f64 {
        let remaining = self.remaining_mins(now);
        if remaining <= 0.0 {
            return f64::INFINITY;
        }
        let headroom = (100.0 - current_pct).max(0.0);
        headroom / remaining
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rl(resets_at: i64) -> RateLimit {
        RateLimit {
            used_percentage: Some(0.0),
            resets_at: Some(resets_at),
        }
    }

    #[test]
    fn builds_window_from_rate_limit() {
        let now = 1_000_000;
        let w = Window::from_rate_limit(&rl(now as i64 + 3600), now).unwrap();
        assert_eq!(w.resets_at, now + 3600);
        assert_eq!(w.started_at, now + 3600 - BLOCK_SECS);
    }

    #[test]
    fn past_reset_is_none() {
        let now = 1_000_000;
        assert!(Window::from_rate_limit(&rl(now as i64 - 10), now).is_none());
    }

    #[test]
    fn missing_reset_is_none() {
        let now = 1_000_000;
        let r = RateLimit {
            used_percentage: Some(50.0),
            resets_at: None,
        };
        assert!(Window::from_rate_limit(&r, now).is_none());
    }

    #[test]
    fn fair_share_at_start_is_headroom_over_block() {
        let now = 1_000_000;
        let w = Window::from_rate_limit(&rl(now as i64 + BLOCK_SECS as i64), now).unwrap();
        let share = w.fair_share(0.0, now);
        // 100% over 5h = 100/300 %/min = 0.333…
        assert!((share - (100.0 / 300.0)).abs() < 1e-9);
    }

    #[test]
    fn fair_share_at_end_is_infinite() {
        let now = 1_000_000;
        let w = Window {
            started_at: now - BLOCK_SECS,
            resets_at: now,
        };
        assert!(w.fair_share(50.0, now).is_infinite());
    }

    #[test]
    fn fair_share_saturated_is_zero() {
        let now = 1_000_000;
        let w = Window::from_rate_limit(&rl(now as i64 + 3600), now).unwrap();
        assert_eq!(w.fair_share(100.0, now), 0.0);
        assert_eq!(w.fair_share(120.0, now), 0.0);
    }
}
