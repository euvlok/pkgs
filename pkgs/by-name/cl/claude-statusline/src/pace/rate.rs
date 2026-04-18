//! Time-windowed rate estimator.
//!
//! Replaces the previous per-sample EWMA — which ignored wall-clock gaps
//! between samples and therefore let bursts of closely-spaced renders
//! dilute the estimate independently of real time. This one takes the
//! samples whose timestamps fall inside a trailing `lookback_mins`
//! window and fits a least-squares line through them; the slope is the
//! `%/min` burn rate.
//!
//! Linear regression over the lookback window is:
//! * **Time-aware.** Clustering of renders doesn't change the weighting.
//! * **Robust to a single noisy endpoint.** A one-off outlier pulls the
//!   slope much less than it would pull an endpoint-slope estimate.
//! * **Smooth under decay.** When the user goes idle, the slope walks
//!   down gradually as the window slides off old bursty samples.

use super::ring::PctSample;

/// Rolling estimate of `%/min` consumed, fit over a trailing wall-clock
/// window of samples.
#[derive(Copy, Clone, Debug)]
pub struct RateEstimate {
    /// Non-negative `%/min`. Server corrections (negative Δpct) are
    /// clamped at 0 at fit time.
    pub rate_pct_per_min: f64,
    /// Count of samples inside the lookback window that contributed to
    /// the fit. `0` means "not enough data" and the caller should treat
    /// the projection as warming up.
    pub samples_consumed: usize,
    /// Wall-clock minutes actually spanned by the samples that fed the
    /// fit. Useful for debug and warmup gating.
    pub span_mins: f64,
}

impl RateEstimate {
    /// Empty / uninformative estimate: zero rate, zero samples.
    #[must_use]
    pub const fn empty() -> Self {
        Self {
            rate_pct_per_min: 0.0,
            samples_consumed: 0,
            span_mins: 0.0,
        }
    }

    /// Fit a `%/min` slope over the subset of `samples` whose timestamps
    /// fall in `[now − lookback_mins·60, now]`.
    ///
    /// Behaviour:
    /// * Samples are assumed already sorted ascending by `ts_unix`
    ///   (`pace::compute` guarantees this).
    /// * If fewer than 2 samples fall in the lookback, we extend one
    ///   sample backwards so a newly-started window can still report a
    ///   rate instead of stalling on "warming" for the entire lookback.
    /// * If the span is still under 60 seconds the estimate is
    ///   [`Self::empty`] — too short a window to trust a slope.
    /// * Negative slopes (server rolled `used_percentage` back) clamp to
    ///   zero. We never advertise a negative burn rate.
    #[must_use]
    pub fn from_samples(samples: &[PctSample], lookback_mins: u32, now: u64) -> Self {
        if samples.is_empty() {
            return Self::empty();
        }
        let lookback_secs = u64::from(lookback_mins).saturating_mul(60);
        let cutoff = now.saturating_sub(lookback_secs);

        // Index of the first sample inside the lookback window.
        let first_in = samples.iter().position(|s| s.ts_unix >= cutoff);
        let start = match first_in {
            // All samples are already inside the window.
            Some(0) => 0,
            // Extend one sample backwards so we can fit a line even when
            // only a single sample has arrived since the lookback began.
            Some(i) => i - 1,
            // Every sample is older than the lookback — use the tail two.
            None => samples.len().saturating_sub(2),
        };
        let window = &samples[start..];
        if window.len() < 2 {
            return Self::empty();
        }

        // Fit y = a + b·t via ordinary least squares. Work in seconds
        // relative to the earliest sample to keep the numbers small.
        let t0 = window[0].ts_unix as i128;
        let n = window.len() as f64;
        let mut sum_t = 0.0f64;
        let mut sum_y = 0.0f64;
        for s in window {
            sum_t += (s.ts_unix as i128 - t0) as f64;
            sum_y += s.used_pct;
        }
        let mean_t = sum_t / n;
        let mean_y = sum_y / n;
        let mut cov = 0.0f64;
        let mut var_t = 0.0f64;
        for s in window {
            let dt = (s.ts_unix as i128 - t0) as f64 - mean_t;
            let dy = s.used_pct - mean_y;
            cov += dt * dy;
            var_t += dt * dt;
        }
        let span_secs = (window.last().unwrap().ts_unix - window.first().unwrap().ts_unix) as f64;
        if var_t == 0.0 || span_secs < 60.0 {
            return Self::empty();
        }
        let slope_per_sec = cov / var_t;
        let rate_per_min = (slope_per_sec * 60.0).max(0.0);

        Self {
            rate_pct_per_min: rate_per_min,
            samples_consumed: window.len(),
            span_mins: span_secs / 60.0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(ts: u64, pct: f64) -> PctSample {
        PctSample { ts_unix: ts, used_pct: pct }
    }

    #[test]
    fn empty_input_is_empty() {
        let e = RateEstimate::from_samples(&[], 20, 1_000);
        assert_eq!(e.rate_pct_per_min, 0.0);
        assert_eq!(e.samples_consumed, 0);
    }

    #[test]
    fn single_sample_is_empty() {
        let e = RateEstimate::from_samples(&[sample(0, 10.0)], 20, 0);
        assert_eq!(e.samples_consumed, 0);
    }

    #[test]
    fn steady_rate_is_recovered_exactly() {
        // 1%/min for 20 min.
        let mut s = Vec::new();
        for i in 0..=20u64 {
            s.push(sample(i * 60, i as f64));
        }
        let e = RateEstimate::from_samples(&s, 30, 20 * 60);
        assert!((e.rate_pct_per_min - 1.0).abs() < 1e-9, "got {}", e.rate_pct_per_min);
    }

    #[test]
    fn clustered_renders_do_not_bias_the_estimate() {
        // 30 renders in 10 seconds during a burst at t≈600s, then idle.
        // Rate fit over the lookback should still reflect the actual
        // per-minute slope, not the clustering.
        let mut s = vec![sample(0, 0.0), sample(300, 5.0), sample(600, 10.0)];
        for i in 0..30 {
            s.push(sample(600 + i, 10.0));
        }
        s.push(sample(900, 10.0));
        let e = RateEstimate::from_samples(&s, 20, 900);
        // True average slope 0→10 over 900s = 0.667 %/min. Allow slack
        // because the clustered points at t=600 weight that region.
        assert!(e.rate_pct_per_min > 0.4, "too low: {}", e.rate_pct_per_min);
        assert!(e.rate_pct_per_min < 1.2, "too high: {}", e.rate_pct_per_min);
    }

    #[test]
    fn idle_decays_rate_gradually() {
        // Burst at the start, then idle samples at the same percentage.
        // Over a 20-minute lookback the slope should be a small positive
        // number (dominated by flat tail), not the original burst rate.
        let mut s = vec![sample(0, 0.0), sample(60, 5.0)];
        for i in 2..=20u64 {
            s.push(sample(i * 60, 5.0));
        }
        let e = RateEstimate::from_samples(&s, 20, 20 * 60);
        // Slope of 20 points with only the first stepping from 0→5.
        // Should be well below the peak 5%/min burst rate.
        assert!(e.rate_pct_per_min < 1.0, "expected decay, got {}", e.rate_pct_per_min);
    }

    #[test]
    fn window_slides_past_old_samples() {
        // Burst early in the day, then long idle.
        // With lookback=20min and now far past the burst, the fit should
        // only see the flat idle samples and report zero rate.
        let mut s = vec![sample(0, 0.0), sample(60, 10.0)];
        for i in 2..=60u64 {
            s.push(sample(i * 60, 10.0));
        }
        let e = RateEstimate::from_samples(&s, 20, 60 * 60);
        assert!(e.rate_pct_per_min.abs() < 1e-6, "got {}", e.rate_pct_per_min);
    }

    #[test]
    fn negative_slope_clamps_to_zero() {
        // Server correction: percentages walk backwards. Treat as no burn.
        let s = [sample(0, 50.0), sample(60, 45.0), sample(120, 40.0)];
        let e = RateEstimate::from_samples(&s, 20, 120);
        assert_eq!(e.rate_pct_per_min, 0.0);
    }

    #[test]
    fn span_under_one_minute_is_empty() {
        let s = [sample(0, 0.0), sample(30, 1.0)];
        let e = RateEstimate::from_samples(&s, 20, 30);
        assert_eq!(e.samples_consumed, 0);
    }

    #[test]
    fn small_rate_change_produces_small_estimate_change() {
        // Regression test for the "wild jumps" bug: a single extra idle
        // sample should nudge the estimate, not halve it.
        let mut before = Vec::new();
        for i in 0..=10u64 {
            before.push(sample(i * 60, i as f64 * 2.0)); // 2%/min
        }
        let mut after = before.clone();
        after.push(sample(11 * 60, 20.0)); // flat: no change
        let e_before = RateEstimate::from_samples(&before, 20, 10 * 60);
        let e_after = RateEstimate::from_samples(&after, 20, 11 * 60);
        let delta = (e_before.rate_pct_per_min - e_after.rate_pct_per_min).abs();
        // One extra flat minute shouldn't move a 2%/min estimate by more
        // than ~0.3%/min.
        assert!(delta < 0.3, "delta={delta} before={} after={}", e_before.rate_pct_per_min, e_after.rate_pct_per_min);
    }
}
