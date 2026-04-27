//! Default public TOML configuration.

use super::schema::{
    CacheSegmentConfig, ClockSegmentConfig, ColorMode, Config, ContextFormat, ContextSegmentConfig,
    DiffSegmentConfig, DirSegmentConfig, DirStyle, DisplayConfig, EnvSegmentConfig, HyperlinksMode,
    IconSetConfig, ModelSegmentConfig, PaceGlyphsConfig, PaceSegmentConfig, RateLimitWindow,
    RateLimitsSegmentConfig, SegmentConfig, StatuslineConfig, TemplateSegmentConfig,
    ThemeModeConfig, VcsSegmentConfig,
};

impl Default for Config {
    fn default() -> Self {
        let mut segments = std::collections::BTreeMap::new();
        segments.insert(
            "dir".to_string(),
            SegmentConfig::Dir(DirSegmentConfig {
                style: DirStyle::Home,
            }),
        );
        segments.insert(
            "context".to_string(),
            SegmentConfig::Context(ContextSegmentConfig::default()),
        );
        segments.insert(
            "quota".to_string(),
            SegmentConfig::RateLimits(RateLimitsSegmentConfig::default()),
        );
        segments.insert(
            "pace".to_string(),
            SegmentConfig::Pace(PaceSegmentConfig::default()),
        );
        segments.insert(
            "vcs".to_string(),
            SegmentConfig::Vcs(VcsSegmentConfig::default()),
        );
        segments.insert(
            "model".to_string(),
            SegmentConfig::Model(ModelSegmentConfig::default()),
        );
        segments.insert(
            "changes".to_string(),
            SegmentConfig::Diff(DiffSegmentConfig::default()),
        );
        segments.insert(
            "elapsed".to_string(),
            SegmentConfig::Clock(ClockSegmentConfig::default()),
        );
        segments.insert(
            "cache".to_string(),
            SegmentConfig::Cache(CacheSegmentConfig::default()),
        );
        Self {
            version: 1,
            display: DisplayConfig::default(),
            statusline: StatuslineConfig::default(),
            segments,
        }
    }
}

impl Default for DisplayConfig {
    fn default() -> Self {
        Self {
            format: super::schema::OutputFormat::Text,
            color: ColorMode::Auto,
            theme: ThemeModeConfig::Auto,
            icons: IconSetConfig::Emoji,
            separator: " │ ".to_string(),
            align: true,
            hyperlinks: HyperlinksMode::Auto,
        }
    }
}

impl Default for StatuslineConfig {
    fn default() -> Self {
        Self {
            lines: vec![
                vec![
                    "dir".to_string(),
                    "context".to_string(),
                    "quota".to_string(),
                    "pace".to_string(),
                    "vcs".to_string(),
                ],
                vec![
                    "model".to_string(),
                    "changes".to_string(),
                    "elapsed".to_string(),
                    "cache".to_string(),
                ],
            ],
        }
    }
}

impl Default for DirSegmentConfig {
    fn default() -> Self {
        Self {
            style: DirStyle::Basename,
        }
    }
}

impl Default for VcsSegmentConfig {
    fn default() -> Self {
        Self {
            show_hash: true,
            show_bookmark: true,
            show_dirty: true,
            show_stash: true,
            show_ahead_behind: true,
        }
    }
}

impl Default for ModelSegmentConfig {
    fn default() -> Self {
        Self { shorten: true }
    }
}

impl Default for ContextSegmentConfig {
    fn default() -> Self {
        Self {
            format: ContextFormat::Auto,
            show_output_tokens: true,
        }
    }
}

impl Default for RateLimitsSegmentConfig {
    fn default() -> Self {
        Self {
            show: vec![RateLimitWindow::FiveHour, RateLimitWindow::SevenDay],
            seven_day_threshold: 80,
            show_countdown: true,
        }
    }
}

impl Default for ClockSegmentConfig {
    fn default() -> Self {
        Self {
            show_api_time: true,
        }
    }
}

impl Default for PaceSegmentConfig {
    fn default() -> Self {
        Self {
            lookback_mins: 20,
            cool_below: 0.9,
            hot_above: 1.2,
            warmup_mins: 10,
            glyphs: PaceGlyphsConfig::Emoji,
            debug: false,
        }
    }
}

impl Default for EnvSegmentConfig {
    fn default() -> Self {
        Self {
            key: String::new(),
            prefix: String::new(),
            style: None,
            hide_empty: true,
        }
    }
}

impl Default for TemplateSegmentConfig {
    fn default() -> Self {
        Self {
            template: String::new(),
            style: None,
            hide_empty: true,
        }
    }
}
