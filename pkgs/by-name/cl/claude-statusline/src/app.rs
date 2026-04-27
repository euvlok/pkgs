//! Application-level orchestration.
//!
//! This module keeps the render decision tree testable and leaves `main.rs`
//! focused on CLI parsing, completions, panic fallback, and stdout.

use std::borrow::Cow;
use std::io::Read as _;

use crate::cli::{Cli, ColorChoice};
use crate::config;
use crate::input::{Input, InputSource};
use crate::pace::PaceSettings;
use crate::render::colors::Palette;
use crate::render::icons::{IconSet, Icons};
use crate::render::layout::Layout;
use crate::render::preview::preview;
use crate::render::render_with_pace;
use crate::settings::Settings;
use crate::theme::{self, ThemeMode};

const MAX_PAYLOAD: u64 = 1 << 20;

#[derive(Debug)]
pub struct PreviewOutput {
    pub layout: Layout,
    pub line: String,
}

pub fn resolved_icons(icon_set: IconSet, separator: Option<&str>) -> Cow<'static, Icons> {
    let base = icon_set.icons();
    match separator {
        Some(sep) => {
            let mut icons = base.clone();
            icons.sep = Cow::Owned(sep.to_owned());
            Cow::Owned(icons)
        }
        None => Cow::Borrowed(base),
    }
}

pub fn palette_for(color: ColorChoice, theme_mode: ThemeMode) -> Palette {
    if matches!(color, ColorChoice::Never) {
        Palette::dark()
    } else {
        Palette::for_theme(theme::detect(theme_mode))
    }
}

pub fn parse_input(json: Option<&str>, reader: impl std::io::Read) -> Input {
    if let Some(json) = json {
        return serde_json::from_str(json).unwrap_or_default();
    }

    // serde_json::from_reader is ~2x slower than slurp-then-parse:
    // it round-trips every byte through Read::read_buf and can't
    // see the input length up front. Claude Code payloads are a
    // few KB; cap at 1 MiB so a runaway producer can't OOM us.
    let mut buf = Vec::with_capacity(4096);
    if reader.take(MAX_PAYLOAD).read_to_end(&mut buf).is_ok() {
        serde_json::from_slice(&buf).unwrap_or_default()
    } else {
        Input::default()
    }
}

pub fn preview_output(
    cli: &Cli,
    icons: &Icons,
    settings: &Settings,
    palette: &Palette,
) -> PreviewOutput {
    let layout = config::load(
        cli.layout.layout.as_deref(),
        cli.layout.config.as_deref(),
        &cli.layout.exclude,
    );
    let line = preview(icons, &layout, settings, palette);
    PreviewOutput { layout, line }
}

pub fn render_statusline(
    cli: &Cli,
    input: &Input,
    icons: &Icons,
    settings: &Settings,
    pace_settings: &PaceSettings,
    palette: &Palette,
) -> String {
    let default_layout = match input.source {
        InputSource::Claude => Layout::two_line(),
        InputSource::Codex => Layout::one_line(),
    };
    let layout = config::load_with_default(
        cli.layout.layout.as_deref(),
        cli.layout.config.as_deref(),
        &cli.layout.exclude,
        default_layout,
    );
    render_with_pace(input, icons, &layout, settings, pace_settings, palette)
}

pub fn fallback_dir() -> String {
    Input::default().dir_name()
}
