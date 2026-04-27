#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::missing_const_for_fn,
    clippy::redundant_closure
)]

//! Benchmarks for formatting helpers, config parsing, palette construction,
//! and segment operations.

use agent_statusline::config::{Config, ResolvedConfig, resolve};
use agent_statusline::render::colors::Palette;
use agent_statusline::render::format::{humanize_duration, humanize_tokens, shorten_model};
use agent_statusline::render::segment::Segment;
use agent_statusline::theme::ThemeMode;

fn main() {
    divan::main();
}

#[divan::bench]
fn config_toml_parse() -> Config {
    toml::from_str(divan::black_box(
        r#"
version = 1

[statusline]
lines = [["dir", "context", "quota"], ["model", "changes"]]

[segments.dir]
type = "dir"

[segments.context]
type = "context"

[segments.quota]
type = "rate-limits"

[segments.model]
type = "model"

[segments.changes]
type = "diff"
"#,
    ))
    .unwrap()
}

#[divan::bench]
fn config_default_resolve() -> ResolvedConfig {
    resolve::resolve(Config::default())
}

#[divan::bench]
fn config_toml_serialize(bencher: divan::Bencher<'_, '_>) {
    let config = Config::default();
    bencher.bench(|| toml::to_string(divan::black_box(&config)).unwrap());
}

#[divan::bench(args = [0_u64, 999, 34_500, 1_234_567, 999_999_999])]
fn fmt_humanize_tokens(n: u64) -> String {
    humanize_tokens(divan::black_box(n))
}

#[divan::bench(args = [0_i64, 45, 750, 5_000, 90_000, 31_536_000])]
fn fmt_humanize_duration(secs: i64) -> String {
    humanize_duration(divan::black_box(secs))
}

#[divan::bench(args = [
    "Haiku",
    "Sonnet 4.5",
    "Opus 4.6 (1M context)",
    "Claude Opus 4.6 with extra (parens) and 4.5 versions",
])]
fn fmt_shorten_model(name: &str) -> &str {
    shorten_model(divan::black_box(name))
}

#[divan::bench(args = [0_u32, 49, 50, 74, 75, 100])]
fn palette_color_for_pct(pct: u32) -> anstyle::Style {
    let pal = Palette::dark();
    pal.color_for_pct(divan::black_box(pct), 50, 75)
}

#[divan::bench(args = [0_u64, 100_000, 200_000, 300_000, 500_000])]
fn palette_color_for_token_count(tokens: u64) -> anstyle::Style {
    let pal = Palette::dark();
    pal.color_for_token_count(divan::black_box(tokens))
}

#[divan::bench]
fn palette_for_theme_dark() -> Palette {
    Palette::for_theme(divan::black_box(ThemeMode::Dark))
}

#[divan::bench]
fn palette_for_theme_light() -> Palette {
    Palette::for_theme(divan::black_box(ThemeMode::Light))
}

#[divan::bench]
fn segment_plain(bencher: divan::Bencher<'_, '_>) {
    bencher
        .with_inputs(|| Segment::droppable())
        .bench_local_values(|s| s.plain("branch-name"));
}

#[divan::bench]
fn segment_styled(bencher: divan::Bencher<'_, '_>) {
    let style = anstyle::AnsiColor::Green.on_default();
    bencher
        .with_inputs(|| Segment::droppable())
        .bench_local_values(|s| s.styled("+342", style));
}

#[divan::bench(args = [1_usize, 3, 6, 10])]
fn segment_width(bencher: divan::Bencher<'_, '_>, cells: usize) {
    let mut s = Segment::droppable();
    for i in 0..cells {
        s.append_plain(format!("cell{i}"));
    }
    bencher.bench(|| s.width());
}

#[divan::bench]
fn segment_write_to(bencher: divan::Bencher<'_, '_>) {
    let pal = Palette::dark();
    let s = Segment::droppable()
        .styled("+342", pal.green)
        .plain(" ")
        .styled("-89", pal.red);
    bencher.bench(|| {
        let mut out = String::new();
        s.write_to(&mut out);
        out
    });
}
