//! Benchmarks for the pace pipeline: rate estimation (Theil-Sen weighted
//! median is O(n²) in the dedup'd sample count, so worth pinning), window
//! math, projection classification, and the format → segment step.

use std::time::Duration;

use claude_statusline::input::{Input, RateLimit, RateLimits};
use claude_statusline::pace::format::{format_projected_pct, render as pace_render};
use claude_statusline::pace::glyphs::{EMOJI, MDI, TEXT};
use claude_statusline::pace::projection::{PaceState, Projection, classify};
use claude_statusline::pace::rate::RateEstimate;
use claude_statusline::pace::window::{BLOCK_SECS, Window};
use claude_statusline::pace::{PaceSettings, PctSample};
use claude_statusline::render::colors::Palette;

fn main() {
    divan::main();
}

const NOW: u64 = 1_700_000_000;

fn steady_samples(n: usize) -> Vec<PctSample> {
    // n samples one per minute ramping from 0% → ~n%, plus a flat tail of
    // duplicates so the dedup_runs path is exercised.
    let mut out = Vec::with_capacity(n + 8);
    let start = NOW - (n as u64) * 60;
    for i in 0..n {
        out.push(PctSample {
            ts_unix: start + i as u64 * 60,
            used_pct: i as f64 * 0.5,
        });
    }
    let tail_pct = out.last().map_or(0.0, |s| s.used_pct);
    let tail_ts = out.last().map_or(NOW, |s| s.ts_unix);
    for k in 1..=8 {
        out.push(PctSample {
            ts_unix: tail_ts + k,
            used_pct: tail_pct,
        });
    }
    out
}

const SAMPLE_COUNTS: &[usize] = &[8, 32, 128, 256];

#[divan::bench(args = SAMPLE_COUNTS)]
fn rate_from_samples(bencher: divan::Bencher<'_, '_>, n: usize) {
    let samples = steady_samples(n);
    bencher.bench(|| RateEstimate::from_samples(divan::black_box(&samples), 20, NOW));
}

#[divan::bench]
fn rate_empty_input() -> RateEstimate {
    RateEstimate::from_samples(divan::black_box(&[]), 20, NOW)
}

#[divan::bench]
fn rate_under_min_span() -> RateEstimate {
    // Two close samples → returns empty quickly. Pins the early-exit cost.
    let s = [
        PctSample { ts_unix: NOW - 30, used_pct: 0.0 },
        PctSample { ts_unix: NOW, used_pct: 1.0 },
    ];
    RateEstimate::from_samples(divan::black_box(&s), 20, NOW)
}

fn window() -> Window {
    Window {
        started_at: NOW - 30 * 60,
        resets_at: NOW - 30 * 60 + BLOCK_SECS,
    }
}

#[divan::bench]
fn window_from_rate_limit(bencher: divan::Bencher<'_, '_>) {
    let rl = RateLimit {
        used_percentage: Some(13.0),
        resets_at: Some((NOW + 4 * 3600) as i64),
    };
    bencher.bench(|| Window::from_rate_limit(divan::black_box(&rl), NOW));
}

#[divan::bench]
fn window_fair_share(bencher: divan::Bencher<'_, '_>) {
    let w = window();
    bencher.bench(|| w.fair_share(divan::black_box(20.0), NOW));
}

#[divan::bench(args = [0.0_f64, 0.3, 1.5, 3.0])]
fn projection_classify(rate: f64) -> Projection {
    let w = window();
    let est = RateEstimate {
        rate_pct_per_min: rate,
        samples_consumed: 8,
        span_mins: 20.0,
    };
    classify(divan::black_box(&w), 20.0, &est, &PaceSettings::default(), NOW)
}

#[divan::bench(args = [0.0_f64, 42.0, 97.4, 142.6, 999.0, f64::INFINITY])]
fn fmt_projected_pct(pct: f64) -> String {
    format_projected_pct(divan::black_box(pct))
}

fn projection(state: PaceState, projected: f64, current: f64) -> Projection {
    Projection {
        state,
        current_pct: current,
        rate_pct_per_min: 0.3,
        fair_share_pct_per_min: 0.5,
        projected_pct_at_reset: projected,
        remaining: Duration::from_secs(2 * 3600),
        cap_eta: Some(Duration::from_secs(47 * 60)),
        rest_to_safe: Some(Duration::from_secs(32 * 60)),
    }
}

#[divan::bench]
fn pace_render_hot(bencher: divan::Bencher<'_, '_>) {
    let p = projection(PaceState::TooHot, 142.0, 60.0);
    let pal = Palette::dark();
    bencher.bench(|| pace_render(divan::black_box(&p), &EMOJI, &pal));
}

#[divan::bench]
fn pace_render_cool(bencher: divan::Bencher<'_, '_>) {
    let p = projection(PaceState::Cool, 34.0, 12.0);
    let pal = Palette::dark();
    bencher.bench(|| pace_render(divan::black_box(&p), &MDI, &pal));
}

#[divan::bench]
fn pace_render_cold(bencher: divan::Bencher<'_, '_>) {
    let p = projection(PaceState::ColdStart, 0.0, 2.0);
    let pal = Palette::dark();
    bencher.bench(|| pace_render(divan::black_box(&p), &TEXT, &pal));
}

#[divan::bench]
fn pace_segment_end_to_end(bencher: divan::Bencher<'_, '_>) {
    // Hot path on real input: stdin's `used_percentage` + `resets_at`
    // → window → ring load (cold cache likely) → rate → classify → format.
    let input = Input {
        rate_limits: RateLimits {
            five_hour: RateLimit {
                used_percentage: Some(20.0),
                resets_at: Some((NOW + 4 * 3600) as i64),
            },
            seven_day: RateLimit::default(),
        },
        ..Default::default()
    };
    let settings = PaceSettings {
        warmup_mins: 0,
        ..PaceSettings::default()
    };
    let pal = Palette::dark();
    bencher.bench(|| {
        claude_statusline::pace::pace(divan::black_box(&input), &settings, &pal, NOW)
    });
}
