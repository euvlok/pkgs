//! TOML configuration loading, schema generation, defaults, and resolution.

use std::path::{Path, PathBuf};

pub mod defaults;
pub mod resolve;
pub mod schema;

pub use resolve::{ConfigWarning, ResolvedConfig, ResolvedDisplay, ResolvedSegment};
pub use schema::{Config, OutputFormat};

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("failed to read config `{path}`: {source}")]
    Read {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("failed to parse config `{path}`: {source}")]
    Parse {
        path: PathBuf,
        source: toml::de::Error,
    },
}

#[derive(Debug)]
pub struct LoadedConfig {
    pub config: Config,
    pub path: Option<PathBuf>,
    pub warnings: Vec<ConfigWarning>,
}

pub fn default_config_path() -> Option<PathBuf> {
    Some(
        dirs::config_dir()?
            .join("claude-statusline")
            .join("config.toml"),
    )
}

pub fn load(path: Option<&Path>) -> Result<LoadedConfig, ConfigError> {
    let Some(path) = path.map(Path::to_path_buf).or_else(default_config_path) else {
        return Ok(default_loaded());
    };
    if !path.exists() {
        return Ok(default_loaded());
    }
    let text = std::fs::read_to_string(&path).map_err(|source| ConfigError::Read {
        path: path.clone(),
        source,
    })?;
    let config = toml::from_str::<Config>(&text).map_err(|source| ConfigError::Parse {
        path: path.clone(),
        source,
    })?;
    Ok(LoadedConfig {
        config,
        path: Some(path),
        warnings: Vec::new(),
    })
}

pub fn load_or_default(path: Option<&Path>) -> LoadedConfig {
    match load(path) {
        Ok(loaded) => loaded,
        Err(err) => {
            let mut loaded = default_loaded();
            loaded.warnings.push(ConfigWarning {
                message: err.to_string(),
            });
            loaded
        }
    }
}

fn default_loaded() -> LoadedConfig {
    LoadedConfig {
        config: Config::default(),
        path: None,
        warnings: Vec::new(),
    }
}
