//! Turns loaded TOML into render-ready layout data.

use serde::Serialize;

use super::schema::{Config, DisplayConfig, SegmentConfig};

#[derive(Debug, Clone)]
pub struct ResolvedConfig {
    pub source: Config,
    pub display: ResolvedDisplay,
    pub lines: Vec<Vec<ResolvedSegment>>,
    pub warnings: Vec<ConfigWarning>,
}

#[derive(Debug, Clone)]
pub struct ResolvedDisplay {
    pub config: DisplayConfig,
}

#[derive(Debug, Clone)]
pub struct ResolvedSegment {
    pub id: String,
    pub config: SegmentConfig,
}

#[derive(Debug, Clone, Serialize)]
pub struct ConfigWarning {
    pub message: String,
}

pub fn resolve(config: Config) -> ResolvedConfig {
    let mut warnings = Vec::new();
    let mut lines: Vec<Vec<ResolvedSegment>> = config
        .statusline
        .lines
        .iter()
        .map(|line| {
            line.iter()
                .filter_map(|id| match config.segments.get(id) {
                    Some(segment) => Some(ResolvedSegment {
                        id: id.clone(),
                        config: segment.clone(),
                    }),
                    None => {
                        warnings.push(ConfigWarning {
                            message: format!("unknown segment id `{id}`"),
                        });
                        None
                    }
                })
                .collect::<Vec<_>>()
        })
        .filter(|line| !line.is_empty())
        .collect();

    let mut source = config;
    if lines.is_empty() {
        warnings.push(ConfigWarning {
            message: "statusline resolved to no segments; using default config".to_string(),
        });
        source = Config::default();
        lines = source
            .statusline
            .lines
            .iter()
            .filter_map(|line| {
                let resolved = line
                    .iter()
                    .filter_map(|id| {
                        source.segments.get(id).map(|segment| ResolvedSegment {
                            id: id.clone(),
                            config: segment.clone(),
                        })
                    })
                    .collect::<Vec<_>>();
                (!resolved.is_empty()).then_some(resolved)
            })
            .collect();
    }

    ResolvedConfig {
        display: ResolvedDisplay {
            config: source.display.clone(),
        },
        source,
        lines,
        warnings,
    }
}
