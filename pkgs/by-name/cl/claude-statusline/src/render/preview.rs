//! `--preview`: render the layout against a hand-crafted sample input.
//!
//! Shows the user what their `--layout` choice will actually look
//! like without having to pipe a real Claude Code payload through stdin.
//!
//! The sample input is intentionally "interesting": every optional
//! field is populated, so each segment has something to render. We also
//! synthesise a fake VCS segment by hand instead of touching the real
//! repo - that way the preview is reproducible regardless of where the
//! user invokes it from, and a user without `gix`/`jj-lib` data still
//! sees the segment in the output.

use crate::input::{
    ContextUsage, ContextWindow, Cost, Input, Model, RateLimit, RateLimits, Workspace,
};
use crate::pace::{self, PaceSettings};
use crate::render::colors::Palette;
use crate::render::icons::Icons;
use crate::render::layout::{BuildCtx, Layout};
use crate::render::segment::Segment;
use crate::settings::Settings;

/// Build a fake input + fake VCS segment, then route them through the
/// same `render_lines` pipeline that real renders use. Returned string
/// is multi-line, ANSI-colored, ready to print.
pub fn preview(icons: &Icons, layout: &Layout, settings: &Settings, pal: &Palette) -> String {
    preview_with(icons, layout, settings, pal, None)
}

/// Same as [`preview`] but lets the caller pin a fixed maximum width
/// instead of using the terminal's actual width.
pub fn preview_with(
    icons: &Icons,
    layout: &Layout,
    settings: &Settings,
    pal: &Palette,
    max_cols: Option<usize>,
) -> String {
    let input = sample_input();
    let vcs = Some(sample_vcs(icons, pal));

    let pace_settings = PaceSettings::default();
    let ctx = BuildCtx {
        input: &input,
        icons,
        palette: pal,
        vcs,
        settings,
        pace_settings: &pace_settings,
        now_unix: pace::now_unix(),
    };
    super::render_lines(&ctx, layout, max_cols)
}

fn sample_input() -> Input {
    let cwd = dirs::home_dir()
        .map(|h| h.join("Developer").join("myapp"))
        .and_then(|p| p.to_str().map(str::to_owned))
        .unwrap_or_else(|| "/home/you/Developer/myapp".to_string());

    Input {
        workspace: Workspace {
            current_dir: Some(cwd),
        },
        cwd: None,
        transcript_path: None,
        session_id: None,
        model: Model {
            display_name: Some("Opus 4.6 (1M context)".into()),
        },
        context_window: ContextWindow {
            used_percentage: Some(16.2),
            context_window_size: Some(1_000_000),
            current_usage: ContextUsage {
                input_tokens: 162_000,
                output_tokens: 48_000,
                cache_creation_input_tokens: 0,
                cache_read_input_tokens: 120_000,
            },
        },
        rate_limits: RateLimits {
            five_hour: RateLimit {
                used_percentage: Some(13.0),
                resets_at: Some(now_plus_secs(4 * 3600 + 3 * 60)),
            },
            seven_day: RateLimit {
                used_percentage: Some(85.0),
                resets_at: Some(now_plus_secs(6 * 86400)),
            },
        },
        cost: Cost {
            total_duration_ms: Some(2_340_000),
            total_api_duration_ms: Some(1_260_000),
            total_lines_added: Some(1062),
            total_lines_removed: Some(290),
        },
        ..Input::default()
    }
}

fn now_plus_secs(secs: i64) -> i64 {
    #[expect(clippy::cast_possible_wrap)]
    let now = pace::now_unix() as i64;
    now.saturating_add(secs)
}

fn sample_vcs(icons: &Icons, pal: &Palette) -> Segment {
    let s = Segment::droppable();
    let s = if icons.git.is_empty() {
        s
    } else {
        s.plain(format!("{} ", icons.git))
    };
    s.styled("main", pal.magenta)
        .plain(" ")
        .styled(icons.dirty.to_string(), pal.yellow)
}
