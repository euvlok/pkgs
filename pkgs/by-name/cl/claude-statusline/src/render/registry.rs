//! Built-in segment and enum capability metadata.

use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct Capabilities {
    pub segments: &'static [SegmentTypeSpec],
    pub icon_sets: &'static [&'static str],
    pub theme_modes: &'static [&'static str],
}

#[derive(Debug, Serialize)]
pub struct SegmentTypeSpec {
    #[serde(rename = "type")]
    pub ty: &'static str,
    pub description: &'static str,
    pub input_requirements: &'static [&'static str],
    pub supports_multiple_instances: bool,
    pub settings_schema_ref: &'static str,
}

pub const SEGMENTS: &[SegmentTypeSpec] = &[
    SegmentTypeSpec {
        ty: "dir",
        description: "working directory",
        input_requirements: &["cwd"],
        supports_multiple_instances: true,
        settings_schema_ref: "#/$defs/DirSegmentConfig",
    },
    SegmentTypeSpec {
        ty: "vcs",
        description: "git or jj repository status",
        input_requirements: &["cwd"],
        supports_multiple_instances: true,
        settings_schema_ref: "#/$defs/VcsSegmentConfig",
    },
    SegmentTypeSpec {
        ty: "model",
        description: "agent model display name",
        input_requirements: &["model"],
        supports_multiple_instances: true,
        settings_schema_ref: "#/$defs/ModelSegmentConfig",
    },
    SegmentTypeSpec {
        ty: "diff",
        description: "lines added and removed",
        input_requirements: &["cost"],
        supports_multiple_instances: true,
        settings_schema_ref: "#/$defs/DiffSegmentConfig",
    },
    SegmentTypeSpec {
        ty: "context",
        description: "context-window usage",
        input_requirements: &["context_window"],
        supports_multiple_instances: true,
        settings_schema_ref: "#/$defs/ContextSegmentConfig",
    },
    SegmentTypeSpec {
        ty: "rate-limits",
        description: "5h and 7d quota usage",
        input_requirements: &["rate_limits"],
        supports_multiple_instances: true,
        settings_schema_ref: "#/$defs/RateLimitsSegmentConfig",
    },
    SegmentTypeSpec {
        ty: "clock",
        description: "session elapsed time",
        input_requirements: &["cost"],
        supports_multiple_instances: true,
        settings_schema_ref: "#/$defs/ClockSegmentConfig",
    },
    SegmentTypeSpec {
        ty: "speed",
        description: "token throughput",
        input_requirements: &["cost", "context_window"],
        supports_multiple_instances: true,
        settings_schema_ref: "#/$defs/SpeedSegmentConfig",
    },
    SegmentTypeSpec {
        ty: "cache",
        description: "prompt cache hit ratio",
        input_requirements: &["context_window"],
        supports_multiple_instances: true,
        settings_schema_ref: "#/$defs/CacheSegmentConfig",
    },
    SegmentTypeSpec {
        ty: "pace",
        description: "5h burn-rate projection",
        input_requirements: &["rate_limits"],
        supports_multiple_instances: true,
        settings_schema_ref: "#/$defs/PaceSegmentConfig",
    },
    SegmentTypeSpec {
        ty: "env",
        description: "environment variable text",
        input_requirements: &["environment"],
        supports_multiple_instances: true,
        settings_schema_ref: "#/$defs/EnvSegmentConfig",
    },
    SegmentTypeSpec {
        ty: "template",
        description: "template rendered from input fields",
        input_requirements: &["input"],
        supports_multiple_instances: true,
        settings_schema_ref: "#/$defs/TemplateSegmentConfig",
    },
];

pub const CAPABILITIES: Capabilities = Capabilities {
    segments: SEGMENTS,
    icon_sets: &["emoji", "nerd", "text"],
    theme_modes: &["auto", "dark", "light"],
};
