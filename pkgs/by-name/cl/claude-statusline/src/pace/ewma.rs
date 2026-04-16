//! Pure EWMA tracker over Δpct/Δt.
//!
//! Consumes consecutive `(ts, pct)` samples and emits an exponentially
//! weighted moving average of the per-minute burn rate. No I/O.

use super::ring::PctSample;

/// Rolling estimate of `%/min` consumed.
///
/// `rate_pct_per_min` is the most recent EWMA value across all consecutive
/// sample pairs. When fewer than two samples are supplied the rate is
/// zero and the caller is expected to mark the projection as warming up.
#[derive(Copy, Clone, Debug)]
pub struct EwmaTracker {
    pub alpha: f64,
    pub rate_pct_per_min: f64,
    pub samples_consumed: usize,
}

impl EwmaTracker {
    /// Fold consecutive `(ts, pct)` samples into an EWMA of `Δpct/Δt`.
    ///
    /// * `alpha` is clamped to `[0.0, 1.0]`. At 0 the rate stays at its
    ///   initial value (first observation wins); at 1 the rate is the
    ///   last observation.
    /// * Negative `Δpct` (server correction, window roll) clamp to 0 —
    ///   we never emit a negative burn rate.
    /// * Non-positive `Δt` pairs (clock skew, duplicates) are skipped.
    #[must_use]
    pub fn from_samples(samples: &[PctSample], alpha: f64) -> Self {
        let alpha = alpha.clamp(0.0, 1.0);
        let mut rate = 0.0;
        let mut seeded = false;
        let mut consumed = 0;
        for pair in samples.windows(2) {
            let a = &pair[0];
            let b = &pair[1];
            if b.ts_unix <= a.ts_unix {
                continue;
            }
            let dt_min = (b.ts_unix - a.ts_unix) as f64 / 60.0;
            let dpct = (b.used_pct - a.used_pct).max(0.0);
            let instant = dpct / dt_min;
            if seeded {
                rate = alpha * instant + (1.0 - alpha) * rate;
            } else {
                rate = instant;
                seeded = true;
            }
            consumed += 1;
        }
        Self {
            alpha,
            rate_pct_per_min: rate,
            samples_consumed: consumed,
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
    fn single_sample_has_no_rate() {
        let e = EwmaTracker::from_samples(&[sample(0, 10.0)], 0.2);
        assert_eq!(e.rate_pct_per_min, 0.0);
        assert_eq!(e.samples_consumed, 0);
    }

    #[test]
    fn steady_input_converges_to_rate() {
        // 1% per minute for 20 minutes.
        let mut samples = Vec::new();
        for i in 0..=20 {
            samples.push(sample(i * 60, i as f64));
        }
        let e = EwmaTracker::from_samples(&samples, 0.5);
        assert!((e.rate_pct_per_min - 1.0).abs() < 1e-6, "got {}", e.rate_pct_per_min);
    }

    #[test]
    fn negative_delta_clamps_to_zero() {
        // Server correction: 50% -> 40%. We don't trust a negative burn rate.
        let samples = [sample(0, 50.0), sample(60, 40.0)];
        let e = EwmaTracker::from_samples(&samples, 0.5);
        assert_eq!(e.rate_pct_per_min, 0.0);
    }

    #[test]
    fn clock_skew_skipped() {
        // Second sample has an earlier timestamp: drop the pair.
        let samples = [sample(100, 10.0), sample(50, 12.0)];
        let e = EwmaTracker::from_samples(&samples, 0.5);
        assert_eq!(e.samples_consumed, 0);
    }

    #[test]
    fn alpha_one_takes_last_instant() {
        // 2%/min then 0%/min. alpha=1 → last wins.
        let samples = [sample(0, 0.0), sample(60, 2.0), sample(120, 2.0)];
        let e = EwmaTracker::from_samples(&samples, 1.0);
        assert!(e.rate_pct_per_min.abs() < 1e-9);
    }

    #[test]
    fn alpha_zero_keeps_first_instant() {
        let samples = [sample(0, 0.0), sample(60, 2.0), sample(120, 2.0)];
        let e = EwmaTracker::from_samples(&samples, 0.0);
        assert!((e.rate_pct_per_min - 2.0).abs() < 1e-9);
    }

    #[test]
    fn silent_decay_approaches_zero() {
        // Big burst then idle: synthetic observations at constant pct
        // should decay the EWMA toward 0.
        let mut samples = vec![sample(0, 0.0), sample(60, 5.0)];
        for i in 2..20 {
            samples.push(sample(i * 60, 5.0));
        }
        let e = EwmaTracker::from_samples(&samples, 0.5);
        // After the burst, each subsequent step contributes 0 instant
        // and halves the stored rate (alpha=0.5). Bound well below the
        // initial 5%/min.
        assert!(e.rate_pct_per_min < 0.5, "got {}", e.rate_pct_per_min);
    }
}
