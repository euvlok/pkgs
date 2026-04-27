//! Resolved statusline layout and segment dispatch.

use crate::config::ResolvedSegment;
use crate::config::schema::{
    ContextFormat, DirStyle, PaceGlyphsConfig, SegmentConfig, ThemeModeConfig,
};
use crate::input::Input;
use crate::pace::{PaceGlyphs, PaceSettings};
use crate::render::builders;
use crate::render::colors::Palette;
use crate::render::segment::Segment;
use crate::settings::Settings;

#[derive(Debug)]
pub struct BuildCtx<'a> {
    pub input: &'a Input,
    pub icons: &'a crate::render::icons::Icons,
    pub palette: &'a Palette,
    pub vcs: Option<Segment>,
    pub display: &'a crate::config::ResolvedDisplay,
    pub now_unix: u64,
}

#[derive(Debug, Clone)]
pub struct Layout {
    pub lines: Vec<Vec<ResolvedSegment>>,
}

impl Layout {
    #[must_use]
    pub const fn new(lines: Vec<Vec<ResolvedSegment>>) -> Self {
        Self { lines }
    }

    #[must_use]
    pub fn needs_vcs(&self) -> bool {
        self.lines
            .iter()
            .flatten()
            .any(|s| matches!(s.config, SegmentConfig::Vcs(_)))
    }
}

pub fn build_segment(ctx: &BuildCtx<'_>, spec: &ResolvedSegment) -> Option<Segment> {
    let mut segment = match &spec.config {
        SegmentConfig::Dir(config) => {
            Some(builders::dir(ctx.input, &dir_settings(ctx, config.style)))
        }
        SegmentConfig::Vcs(_) => ctx.vcs.clone(),
        SegmentConfig::Model(config) => {
            builders::model(ctx.input, ctx.icons, ctx.palette, config.shorten)
        }
        SegmentConfig::Diff(_) => builders::diff(ctx.input, ctx.palette),
        SegmentConfig::Context(config) => builders::context_config(
            ctx.input,
            context_format(config.format),
            config.show_output_tokens,
            ctx.palette,
        ),
        SegmentConfig::RateLimits(config) => {
            builders::rate_limits_config(ctx.input, ctx.icons, config, ctx.palette, ctx.now_unix)
        }
        SegmentConfig::Clock(config) => {
            builders::clock_config(ctx.input, ctx.icons, ctx.palette, config.show_api_time)
        }
        SegmentConfig::Speed(_) => builders::speed(ctx.input, ctx.palette),
        SegmentConfig::Cache(_) => builders::cache(ctx.input, ctx.palette),
        SegmentConfig::Pace(config) => {
            let settings = PaceSettings {
                lookback_mins: config.lookback_mins,
                cool_below: config.cool_below,
                hot_above: config.hot_above,
                warmup_mins: config.warmup_mins,
                glyphs: pace_glyphs(config.glyphs),
                debug: config.debug,
            };
            builders::pace(ctx.input, &settings, ctx.palette, ctx.now_unix)
        }
        SegmentConfig::Env(config) => builders::env(config, ctx.palette),
        SegmentConfig::Template(config) => builders::template(config, ctx.input, ctx.palette),
    }?;
    segment.id.clone_from(&spec.id);
    segment.ty = spec.config.ty().to_string();
    Some(segment)
}

fn dir_settings(ctx: &BuildCtx<'_>, style: DirStyle) -> Settings {
    Settings {
        align: ctx.display.config.align,
        dir_style: match style {
            DirStyle::Basename => crate::settings::DirStyle::Basename,
            DirStyle::Full => crate::settings::DirStyle::Full,
            DirStyle::Home => crate::settings::DirStyle::Home,
        },
        context_format: crate::settings::ContextFormat::Auto,
        seven_day_threshold: 80,
        hyperlinks: match ctx.display.config.hyperlinks {
            crate::config::schema::HyperlinksMode::Always => true,
            crate::config::schema::HyperlinksMode::Never => false,
            crate::config::schema::HyperlinksMode::Auto => {
                use std::io::IsTerminal as _;
                std::io::stdout().is_terminal()
            }
        },
    }
}

const fn context_format(format: ContextFormat) -> crate::settings::ContextFormat {
    match format {
        ContextFormat::Auto => crate::settings::ContextFormat::Auto,
        ContextFormat::Percent => crate::settings::ContextFormat::Percent,
        ContextFormat::Tokens => crate::settings::ContextFormat::Tokens,
    }
}

const fn pace_glyphs(glyphs: PaceGlyphsConfig) -> PaceGlyphs {
    match glyphs {
        PaceGlyphsConfig::Mdi => PaceGlyphs::Mdi,
        PaceGlyphsConfig::Fa => PaceGlyphs::Fa,
        PaceGlyphsConfig::Oct => PaceGlyphs::Oct,
        PaceGlyphsConfig::Emoji => PaceGlyphs::Emoji,
        PaceGlyphsConfig::Text => PaceGlyphs::Text,
    }
}

pub const fn theme_mode(mode: ThemeModeConfig) -> crate::theme::ThemeMode {
    match mode {
        ThemeModeConfig::Auto => crate::theme::ThemeMode::Auto,
        ThemeModeConfig::Dark => crate::theme::ThemeMode::Dark,
        ThemeModeConfig::Light => crate::theme::ThemeMode::Light,
    }
}
