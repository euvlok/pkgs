//! Benchmarks for end-to-end rendering, alignment/fit, and individual
//! segment builders.

use claude_statusline::input::{
    ContextUsage, ContextWindow, Cost, Input, InputSource, Model, RateLimit, RateLimits, Workspace,
};
use claude_statusline::render::builders;
use claude_statusline::render::colors::Palette;
use claude_statusline::render::icons::IconSet;
use claude_statusline::render::layout::Layout;
use claude_statusline::render::segment::Segment;
use claude_statusline::render::{column_widths, fit_with_alignment, render, render_with};
use claude_statusline::settings::Settings;

fn main() {
    divan::main();
}

fn rich_input() -> Input {
    Input {
        source: InputSource::Claude,
        workspace: Workspace {
            current_dir: Some("/Users/flame/Developer/nix-dotfiles/pkgs/claude-statusline".into()),
        },
        cwd: None,
        transcript_path: None,
        session_id: None,
        model: Model {
            display_name: Some("Opus 4.6 (1M context)".into()),
        },
        context_window: ContextWindow {
            used_percentage: Some(2.5),
            context_window_size: Some(1_000_000),
            current_usage: ContextUsage {
                input_tokens: 25_000,
                output_tokens: 8_000,
                cache_creation_input_tokens: 0,
                cache_read_input_tokens: 18_000,
            },
        },
        rate_limits: RateLimits {
            five_hour: RateLimit {
                used_percentage: Some(7.0),
                resets_at: Some(i64::MAX / 4),
            },
            seven_day: RateLimit::default(),
        },
        cost: Cost {
            total_duration_ms: Some(120_000),
            total_api_duration_ms: Some(47_000),
            total_lines_added: Some(12),
            total_lines_removed: Some(3),
        },
    }
}

fn minimal_input() -> Input {
    Input {
        workspace: Workspace {
            current_dir: Some("/tmp/foo".into()),
        },
        ..Default::default()
    }
}

#[divan::bench]
fn render_minimal(bencher: divan::Bencher<'_, '_>) {
    let input = minimal_input();
    let icons = IconSet::Text.icons();
    let layout = Layout::two_line();
    bencher.bench(|| render(divan::black_box(&input), icons, divan::black_box(&layout)));
}

#[divan::bench]
fn render_rich_two_line(bencher: divan::Bencher<'_, '_>) {
    let input = rich_input();
    let icons = IconSet::Text.icons();
    let layout = Layout::two_line();
    bencher.bench(|| render(divan::black_box(&input), icons, divan::black_box(&layout)));
}

#[divan::bench]
fn render_rich_single_line(bencher: divan::Bencher<'_, '_>) {
    let input = rich_input();
    let icons = IconSet::Text.icons();
    let layout = Layout::parse("dir, vcs, model, diff, context, rate_limits").unwrap();
    bencher.bench(|| render(divan::black_box(&input), icons, divan::black_box(&layout)));
}

#[divan::bench]
fn render_rich_nerd_icons(bencher: divan::Bencher<'_, '_>) {
    let input = rich_input();
    let icons = IconSet::Nerd.icons();
    let layout = Layout::two_line();
    bencher.bench(|| render(divan::black_box(&input), icons, divan::black_box(&layout)));
}

#[divan::bench]
fn render_rich_emoji_icons(bencher: divan::Bencher<'_, '_>) {
    let input = rich_input();
    let icons = IconSet::Emoji.icons();
    let layout = Layout::two_line();
    bencher.bench(|| render(divan::black_box(&input), icons, divan::black_box(&layout)));
}

#[divan::bench]
fn render_light_theme(bencher: divan::Bencher<'_, '_>) {
    let input = rich_input();
    let icons = IconSet::Text.icons();
    let layout = Layout::two_line();
    let pal = Palette::light();
    bencher.bench(|| {
        render_with(
            divan::black_box(&input),
            icons,
            divan::black_box(&layout),
            &Settings::default(),
            &pal,
        )
    });
}

const SEGMENT_COUNTS: &[usize] = &[2, 4, 8, 16];

fn make_segments(n: usize) -> Vec<Segment> {
    (0..n)
        .map(|i| {
            let mut s = if i == 0 {
                Segment::anchor()
            } else {
                Segment::droppable()
            };
            s.push_plain(format!("seg{i:02}-{}", "x".repeat(i % 7)));
            s
        })
        .collect()
}

#[divan::bench(args = SEGMENT_COUNTS)]
fn align_column_widths(bencher: divan::Bencher<'_, '_>, n: usize) {
    let lines = vec![make_segments(n), make_segments(n.saturating_sub(1).max(1))];
    bencher.bench(|| column_widths(divan::black_box(&lines)));
}

#[divan::bench(args = SEGMENT_COUNTS)]
fn align_fit_no_overflow(bencher: divan::Bencher<'_, '_>, n: usize) {
    bencher
        .with_inputs(|| vec![make_segments(n), make_segments(n)])
        .bench_local_values(|mut lines| {
            fit_with_alignment(&mut lines, 3, Some(10_000));
            lines
        });
}

#[divan::bench(args = SEGMENT_COUNTS)]
fn align_fit_forces_drops(bencher: divan::Bencher<'_, '_>, n: usize) {
    bencher
        .with_inputs(|| vec![make_segments(n), make_segments(n)])
        .bench_local_values(|mut lines| {
            fit_with_alignment(&mut lines, 3, Some(30));
            lines
        });
}

#[divan::bench]
fn builder_dir(bencher: divan::Bencher<'_, '_>) {
    let input = rich_input();
    let settings = Settings::default();
    bencher.bench(|| builders::dir(divan::black_box(&input), divan::black_box(&settings)));
}

#[divan::bench]
fn builder_model(bencher: divan::Bencher<'_, '_>) {
    let input = rich_input();
    let icons = IconSet::Text.icons();
    let pal = Palette::dark();
    bencher.bench(|| builders::model(divan::black_box(&input), icons, &pal));
}

#[divan::bench]
fn builder_diff(bencher: divan::Bencher<'_, '_>) {
    let input = rich_input();
    let pal = Palette::dark();
    bencher.bench(|| builders::diff(divan::black_box(&input), &pal));
}

#[divan::bench]
fn builder_context(bencher: divan::Bencher<'_, '_>) {
    let input = rich_input();
    let settings = Settings::default();
    let pal = Palette::dark();
    bencher.bench(|| builders::context(divan::black_box(&input), &settings, &pal));
}

#[divan::bench]
fn builder_rate_limits(bencher: divan::Bencher<'_, '_>) {
    let input = rich_input();
    let icons = IconSet::Text.icons();
    let settings = Settings::default();
    let pal = Palette::dark();
    let now = claude_statusline::pace::now_unix();
    bencher.bench(|| {
        builders::rate_limits(divan::black_box(&input), icons, &settings, &pal, now)
    });
}
