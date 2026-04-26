//! Time-windowed rate estimator.
//!
//! Theil–Sen median-of-pairwise-slopes with exponential recency weighting.
//! More robust than OLS to two failure modes that show up in real
//! statusline data:
//!
//! * **Burst clustering.** A render loop produces ~30 identical-pct
//!   samples in 10 seconds. Plain Theil–Sen would see ~450 zero-slope
//!   pairs from that cluster and the median would collapse to 0; OLS
//!   gets pulled toward the cluster but stays above zero. We sidestep
//!   the issue by collapsing equal-`pct` runs to `[first, last]` before
//!   the median, which preserves "stayed flat from t₁ to t₂" without
//!   contributing N² zero pairs.
//! * **Idle decay.** With a recency weight (`τ = lookback/2`) the median
//!   slides toward the flat tail within a minute or two of stopping,
//!   instead of remembering the early burst for the whole lookback.
//!
//! Guardrails (`min_points = 3`, adaptive `min_span = max(60s, 10% of
//! lookback)`) come from `JuanjoFuchs/ccburn`'s burn-rate calculator —
//! they keep a barely-warm window from publishing a wild slope.

use super::ring::PctSample;

/// Rolling estimate of `%/min` consumed.
#[derive(Copy, Clone, Debug)]
pub struct RateEstimate {
    /// Non-negative `%/min`. Server corrections (negative Δpct) are
    /// clamped at 0 at fit time.
    pub rate_pct_per_min: f64,
    /// Count of samples (after run-length dedup) that contributed to
    /// the fit. `0` means "not enough data" and the caller should treat
    /// the projection as warming up.
    pub samples_consumed: usize,
    /// Wall-clock minutes actually spanned by the samples that fed the
    /// fit. Useful for debug and warmup gating.
    pub span_mins: f64,
}

/// Minimum compressed-sample count required to publish a slope. Below
/// this we return [`RateEstimate::empty`] and let the caller stay in
/// warmup. Mirrors `ccburn`'s `min_points = 3`.
const MIN_POINTS: usize = 3;

/// Equal-pct runs longer than 2 collapse to `[first, last]`. Below this
/// epsilon two samples are treated as identical pct.
const PCT_EPS: f64 = 1e-9;

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
    /// * Samples are assumed sorted ascending by `ts_unix`.
    /// * If fewer than 2 samples fall in the lookback, we extend one
    ///   sample backwards so a newly-started window can still report a
    ///   rate instead of stalling for the entire lookback.
    /// * Equal-`pct` runs collapse to `[first, last]` to keep flat
    ///   stretches from injecting N² zero-slope pairs into the median.
    /// * If the post-dedup count is below [`MIN_POINTS`] **or** the
    ///   span is below `max(60s, lookback/10)`, we return empty.
    /// * Negative slopes (server rolled `used_percentage` back) clamp to
    ///   zero. We never advertise a negative burn rate.
    #[must_use]
    pub fn from_samples(samples: &[PctSample], lookback_mins: u32, now: u64) -> Self {
        if samples.len() < 2 {
            return Self::empty();
        }
        let lookback_secs = u64::from(lookback_mins).saturating_mul(60);
        let cutoff = now.saturating_sub(lookback_secs);

        let first_in = samples.iter().position(|s| s.ts_unix >= cutoff);
        let start = match first_in {
            Some(0) => 0,
            Some(i) => i - 1,
            None => samples.len().saturating_sub(2),
        };
        let raw = &samples[start..];
        if raw.len() < 2 {
            return Self::empty();
        }

        let compressed = dedup_runs(raw);
        let (Some(first), Some(last)) = (compressed.first(), compressed.last()) else {
            return Self::empty();
        };
        let span_secs = last.ts_unix.saturating_sub(first.ts_unix) as f64;
        let min_span_secs = (lookback_secs / 10).max(60) as f64;
        if span_secs < min_span_secs {
            return Self::empty();
        }
        if compressed.len() < MIN_POINTS {
            return Self::empty();
        }

        // Pairwise slopes with exponential recency weighting.
        // τ = half the lookback: a pair whose midpoint is `lookback/2`
        // seconds old gets weight `e⁻¹ ≈ 0.37`.
        let tau = (lookback_secs as f64 / 2.0).max(60.0);
        let n = compressed.len();
        let mut weighted: Vec<(f64, f64)> = Vec::with_capacity(n * (n - 1) / 2);
        for i in 0..n {
            for j in (i + 1)..n {
                let ti = compressed[i].ts_unix as i128;
                let tj = compressed[j].ts_unix as i128;
                let dt = (tj - ti) as f64;
                if dt <= 0.0 {
                    continue;
                }
                let slope = (compressed[j].used_pct - compressed[i].used_pct) / dt;
                let t_mid = (ti + tj) as f64 / 2.0;
                let age = (now as f64 - t_mid).max(0.0);
                let w = (-age / tau).exp();
                weighted.push((slope, w));
            }
        }
        if weighted.is_empty() {
            return Self::empty();
        }
        let slope_per_sec = weighted_median(&mut weighted);
        let rate_per_min = (slope_per_sec * 60.0).max(0.0);

        Self {
            rate_pct_per_min: rate_per_min,
            samples_consumed: compressed.len(),
            span_mins: span_secs / 60.0,
        }
    }
}

/// Collapse consecutive equal-`pct` samples to `[first, last]`. Runs of
/// length 1 pass through; longer runs keep only the boundary pair —
/// preserving the temporal extent of a flat stretch without injecting
/// all the intermediate zero-slope pairs into the median.
fn dedup_runs(samples: &[PctSample]) -> Vec<PctSample> {
    samples
        .chunk_by(|a, b| (a.used_pct - b.used_pct).abs() <= PCT_EPS)
        .flat_map(|run| {
            let first = run[0];
            match run.last().copied() {
                Some(last) if last.ts_unix != first.ts_unix => [Some(first), Some(last)],
                _ => [Some(first), None],
            }
        })
        .flatten()
        .collect()
}

/// Weighted median: smallest slope `s*` such that the cumulative weight
/// of slopes `≤ s*` reaches half the total weight.
fn weighted_median(pairs: &mut [(f64, f64)]) -> f64 {
    pairs.sort_unstable_by(|a, b| a.0.total_cmp(&b.0));
    let total: f64 = pairs.iter().map(|p| p.1).sum();
    if total <= 0.0 || !total.is_finite() {
        return pairs[pairs.len() / 2].0;
    }
    let half = total / 2.0;
    let mut acc = 0.0;
    for (slope, w) in pairs.iter() {
        acc += w;
        if acc >= half {
            return *slope;
        }
    }
    pairs.last().map_or(0.0, |p| p.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(ts: u64, pct: f64) -> PctSample {
        PctSample {
            ts_unix: ts,
            used_pct: pct,
        }
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
        // 1%/min for 20 min — every pair slope is exactly 1/min.
        let mut s = Vec::new();
        for i in 0..=20u64 {
            s.push(sample(i * 60, i as f64));
        }
        let e = RateEstimate::from_samples(&s, 30, 20 * 60);
        assert!(
            (e.rate_pct_per_min - 1.0).abs() < 1e-9,
            "got {}",
            e.rate_pct_per_min
        );
    }

    #[test]
    fn clustered_renders_do_not_bias_the_estimate() {
        // 30 renders in 10 seconds during a burst at t≈600s, then idle.
        // Run-length dedup collapses the burst to its [first, last] pair,
        // so the median sees the actual ramp 0→10 over 0..900s, not 450
        // zero-slope pairs.
        let mut s = vec![sample(0, 0.0), sample(300, 5.0), sample(600, 10.0)];
        for i in 0..30 {
            s.push(sample(600 + i, 10.0));
        }
        s.push(sample(900, 10.0));
        let e = RateEstimate::from_samples(&s, 20, 900);
        // True average slope 0→10 over 900s = 0.667 %/min.
        assert!(e.rate_pct_per_min > 0.4, "too low: {}", e.rate_pct_per_min);
        assert!(e.rate_pct_per_min < 1.2, "too high: {}", e.rate_pct_per_min);
    }

    #[test]
    fn idle_decays_rate_gradually() {
        // Burst at the start, then idle samples at the same percentage.
        // Recency weighting + run-length dedup → most weight on the
        // (60..1200) flat pair.
        let mut s = vec![sample(0, 0.0), sample(60, 5.0)];
        for i in 2..=20u64 {
            s.push(sample(i * 60, 5.0));
        }
        let e = RateEstimate::from_samples(&s, 20, 20 * 60);
        assert!(
            e.rate_pct_per_min < 1.0,
            "expected decay, got {}",
            e.rate_pct_per_min
        );
    }

    #[test]
    fn window_slides_past_old_samples() {
        // Burst early in the day, then long idle.
        // With lookback=20min and now far past the burst, the fit should
        // see only the flat idle samples and return zero (or empty).
        let mut s = vec![sample(0, 0.0), sample(60, 10.0)];
        for i in 2..=60u64 {
            s.push(sample(i * 60, 10.0));
        }
        let e = RateEstimate::from_samples(&s, 20, 60 * 60);
        assert!(
            e.rate_pct_per_min.abs() < 1e-6,
            "got {}",
            e.rate_pct_per_min
        );
    }

    #[test]
    fn negative_slope_clamps_to_zero() {
        // Server correction: percentages walk backwards.
        let s = [sample(0, 50.0), sample(60, 45.0), sample(120, 40.0)];
        let e = RateEstimate::from_samples(&s, 20, 120);
        assert_eq!(e.rate_pct_per_min, 0.0);
    }

    #[test]
    fn span_under_min_is_empty() {
        // Under 60s span: too short to trust a slope.
        let s = [sample(0, 0.0), sample(30, 1.0)];
        let e = RateEstimate::from_samples(&s, 20, 30);
        assert_eq!(e.samples_consumed, 0);
    }

    #[test]
    fn fewer_than_three_compressed_points_is_empty() {
        // Two raw samples is below MIN_POINTS regardless of span.
        let s = [sample(0, 0.0), sample(600, 10.0)];
        let e = RateEstimate::from_samples(&s, 20, 600);
        assert_eq!(
            e.samples_consumed, 0,
            "got rate {}",
            e.rate_pct_per_min
        );
    }

    #[test]
    fn small_rate_change_produces_small_estimate_change() {
        // A single extra near-flat sample should nudge the estimate, not halve it.
        let mut before = Vec::new();
        for i in 0..=10u64 {
            before.push(sample(i * 60, i as f64 * 2.0)); // 2%/min
        }
        let mut after = before.clone();
        after.push(sample(11 * 60, 20.0)); // flat: no change
        let e_before = RateEstimate::from_samples(&before, 20, 10 * 60);
        let e_after = RateEstimate::from_samples(&after, 20, 11 * 60);
        let delta = (e_before.rate_pct_per_min - e_after.rate_pct_per_min).abs();
        assert!(
            delta < 0.3,
            "delta={delta} before={} after={}",
            e_before.rate_pct_per_min,
            e_after.rate_pct_per_min
        );
    }

    #[test]
    fn dedup_runs_keeps_first_and_last_of_flat() {
        let s = vec![
            sample(0, 0.0),
            sample(60, 10.0),
            sample(120, 10.0),
            sample(180, 10.0),
            sample(240, 10.0),
            sample(300, 20.0),
        ];
        let out = dedup_runs(&s);
        assert_eq!(out.len(), 4);
        assert_eq!(out[0].ts_unix, 0);
        assert_eq!(out[1].ts_unix, 60);
        assert_eq!(out[2].ts_unix, 240);
        assert_eq!(out[3].ts_unix, 300);
    }

    #[test]
    fn dedup_runs_preserves_distinct_samples() {
        let s = vec![sample(0, 0.0), sample(60, 1.0), sample(120, 2.0)];
        let out = dedup_runs(&s);
        assert_eq!(out, s);
    }

    #[test]
    fn weighted_median_simple() {
        let mut p = vec![(0.0, 1.0), (1.0, 1.0), (2.0, 1.0)];
        assert_eq!(weighted_median(&mut p), 1.0);
    }

    #[test]
    fn weighted_median_skewed_weights() {
        // A heavy weight at slope=0 should dominate three light slopes at 1.
        let mut p = vec![(0.0, 10.0), (1.0, 1.0), (1.0, 1.0), (1.0, 1.0)];
        assert_eq!(weighted_median(&mut p), 0.0);
    }
}
