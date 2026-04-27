//! Public TOML configuration schema.

#![allow(unused_qualifications)]

use std::collections::BTreeMap;

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[schemars(title = "ClaudeStatuslineConfig")]
#[serde(default, rename_all = "kebab-case")]
pub struct Config {
    pub version: u32,
    pub display: DisplayConfig,
    pub statusline: StatuslineConfig,
    pub segments: BTreeMap<String, SegmentConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(default, rename_all = "kebab-case")]
pub struct DisplayConfig {
    pub format: OutputFormat,
    pub color: ColorMode,
    pub theme: ThemeModeConfig,
    pub icons: IconSetConfig,
    pub separator: String,
    pub align: bool,
    pub hyperlinks: HyperlinksMode,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(default, rename_all = "kebab-case")]
pub struct StatuslineConfig {
    pub lines: Vec<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "type", rename_all = "kebab-case")]
pub enum SegmentConfig {
    Dir(DirSegmentConfig),
    Vcs(VcsSegmentConfig),
    Model(ModelSegmentConfig),
    Diff(DiffSegmentConfig),
    Context(ContextSegmentConfig),
    RateLimits(RateLimitsSegmentConfig),
    Clock(ClockSegmentConfig),
    Speed(SpeedSegmentConfig),
    Cache(CacheSegmentConfig),
    Pace(PaceSegmentConfig),
    Env(EnvSegmentConfig),
    Template(TemplateSegmentConfig),
}

impl SegmentConfig {
    pub const fn ty(&self) -> &'static str {
        match self {
            Self::Dir(_) => "dir",
            Self::Vcs(_) => "vcs",
            Self::Model(_) => "model",
            Self::Diff(_) => "diff",
            Self::Context(_) => "context",
            Self::RateLimits(_) => "rate-limits",
            Self::Clock(_) => "clock",
            Self::Speed(_) => "speed",
            Self::Cache(_) => "cache",
            Self::Pace(_) => "pace",
            Self::Env(_) => "env",
            Self::Template(_) => "template",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(default, rename_all = "kebab-case")]
pub struct DirSegmentConfig {
    pub style: DirStyle,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(default, rename_all = "kebab-case")]
pub struct VcsSegmentConfig {
    pub show_hash: bool,
    pub show_bookmark: bool,
    pub show_dirty: bool,
    pub show_stash: bool,
    pub show_ahead_behind: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(default, rename_all = "kebab-case")]
pub struct ModelSegmentConfig {
    pub shorten: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(default, rename_all = "kebab-case")]
pub struct DiffSegmentConfig {}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(default, rename_all = "kebab-case")]
pub struct ContextSegmentConfig {
    pub format: ContextFormat,
    pub show_output_tokens: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(default, rename_all = "kebab-case")]
pub struct RateLimitsSegmentConfig {
    pub show: Vec<RateLimitWindow>,
    pub seven_day_threshold: u32,
    pub show_countdown: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(default, rename_all = "kebab-case")]
pub struct ClockSegmentConfig {
    pub show_api_time: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(default, rename_all = "kebab-case")]
pub struct SpeedSegmentConfig {}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(default, rename_all = "kebab-case")]
pub struct CacheSegmentConfig {}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(default, rename_all = "kebab-case")]
pub struct PaceSegmentConfig {
    pub lookback_mins: u32,
    pub cool_below: f64,
    pub hot_above: f64,
    pub warmup_mins: u32,
    pub glyphs: PaceGlyphsConfig,
    pub debug: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(default, rename_all = "kebab-case")]
pub struct EnvSegmentConfig {
    pub key: String,
    pub prefix: String,
    pub style: Option<String>,
    pub hide_empty: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(default, rename_all = "kebab-case")]
pub struct TemplateSegmentConfig {
    pub template: String,
    pub style: Option<String>,
    pub hide_empty: bool,
}

#[derive(Copy, Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum OutputFormat {
    #[default]
    Text,
    Json,
}

#[derive(Copy, Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum ColorMode {
    #[default]
    Auto,
    Always,
    Never,
}

#[derive(Copy, Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum ThemeModeConfig {
    #[default]
    Auto,
    Dark,
    Light,
}

#[derive(Copy, Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum IconSetConfig {
    Nerd,
    #[default]
    Emoji,
    Text,
}

#[derive(Copy, Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum HyperlinksMode {
    #[default]
    Auto,
    Never,
    Always,
}

#[derive(Copy, Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum DirStyle {
    #[default]
    Basename,
    Full,
    Home,
}

#[derive(Copy, Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum ContextFormat {
    #[default]
    Auto,
    Percent,
    Tokens,
}

#[derive(Copy, Clone, Debug, Eq, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum RateLimitWindow {
    FiveHour,
    SevenDay,
}

#[derive(Copy, Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum PaceGlyphsConfig {
    Mdi,
    Fa,
    Oct,
    #[default]
    Emoji,
    Text,
}
