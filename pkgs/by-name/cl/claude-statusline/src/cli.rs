//! Operational command-line interface.

use std::path::PathBuf;

use clap::{Parser, ValueEnum};

use crate::config::OutputFormat;

#[derive(Parser, Debug)]
#[command(
    version,
    about = "Fast Claude Code / Codex statusline (gix + jj-lib)",
    long_about = "Fast Claude Code / Codex statusline driven by TOML config and JSON introspection.",
    max_term_width = 100
)]
pub struct Cli {
    /// TOML config path (defaults to $XDG_CONFIG_HOME/claude-statusline/config.toml)
    #[arg(
        short = 'c',
        long,
        env = "CLAUDE_STATUSLINE_CONFIG",
        value_name = "PATH"
    )]
    pub config: Option<PathBuf>,

    /// Read the payload from a JSON string instead of stdin
    #[arg(long = "input-json", value_name = "JSON")]
    pub input_json: Option<String>,

    /// Output format for render/defaults/preview
    #[arg(long, value_enum, value_name = "FORMAT")]
    pub format: Option<CliFormat>,

    /// Render the resolved layout against sample data and exit
    #[arg(long, action = clap::ArgAction::SetTrue)]
    pub preview: bool,

    /// Print JSON Schema for the TOML config and exit
    #[arg(long, action = clap::ArgAction::SetTrue)]
    pub schema: bool,

    /// Print the full default config and exit
    #[arg(long, action = clap::ArgAction::SetTrue)]
    pub defaults: bool,

    /// Print machine-readable segment and enum metadata and exit
    #[arg(long, action = clap::ArgAction::SetTrue)]
    pub capabilities: bool,

    /// Print resolved config plus render diagnostics and exit
    #[arg(long, action = clap::ArgAction::SetTrue)]
    pub inspect: bool,
}

impl Cli {
    pub fn format(&self, config_format: OutputFormat) -> OutputFormat {
        self.format.map_or(config_format, Into::into)
    }
}

#[derive(Copy, Clone, Debug, ValueEnum, Eq, PartialEq)]
#[value(rename_all = "lower")]
pub enum CliFormat {
    Text,
    Json,
}

impl From<CliFormat> for OutputFormat {
    fn from(value: CliFormat) -> Self {
        match value {
            CliFormat::Text => Self::Text,
            CliFormat::Json => Self::Json,
        }
    }
}
