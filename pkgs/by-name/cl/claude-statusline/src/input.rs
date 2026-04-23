//! Serde structs for the Claude Code / Codex input payload.
//!
//! Claude Code streams a rich status payload on stdin; Codex exposes several
//! smaller JSON hook payloads instead. We normalize both into one lenient
//! `Input` so the renderer can stay provider-agnostic and simply omit segments
//! whose backing data is unavailable.

use serde::Deserialize;
use serde::Deserializer;
use serde::de;
use serde_json::Value;

#[derive(Debug, Default)]
pub struct Input {
    pub workspace: Workspace,
    pub cwd: Option<String>,
    pub transcript_path: Option<String>,
    pub session_id: Option<String>,
    pub model: Model,
    pub context_window: ContextWindow,
    pub rate_limits: RateLimits,
    pub cost: Cost,
}

impl<'de> Deserialize<'de> for Input {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = Value::deserialize(deserializer)?;
        Self::from_json_value(value).map_err(de::Error::custom)
    }
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct Workspace {
    pub current_dir: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct Model {
    pub display_name: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct ContextWindow {
    pub used_percentage: Option<f64>,
    pub context_window_size: Option<u64>,
    pub current_usage: ContextUsage,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct ContextUsage {
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cache_creation_input_tokens: u64,
    pub cache_read_input_tokens: u64,
}

impl ContextUsage {
    /// Total input-side tokens (input + cache creation + cache read).
    #[must_use]
    pub const fn total(&self) -> u64 {
        self.input_tokens + self.cache_creation_input_tokens + self.cache_read_input_tokens
    }

    /// Fraction of input tokens served from cache, as a percentage.
    /// Returns `None` when there's no meaningful denominator.
    #[must_use]
    pub fn cache_hit_pct(&self) -> Option<u32> {
        let denom = self.total();
        if denom == 0 {
            return None;
        }
        Some(((self.cache_read_input_tokens as f64 / denom as f64) * 100.0).round() as u32)
    }
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct RateLimits {
    pub five_hour: RateLimit,
    pub seven_day: RateLimit,
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct RateLimit {
    pub used_percentage: Option<f64>,
    /// Unix epoch seconds at which this window resets. When present we
    /// render a `1h 23m left` countdown next to the percentage.
    pub resets_at: Option<i64>,
}

/// Claude Code optionally pre-computes the session's API-equivalent cost.
///
/// Passed down on stdin. When present, mirroring ccusage's "auto" mode,
/// we prefer this number over walking the transcript ourselves.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct Cost {
    pub total_cost_usd: Option<f64>,
    pub total_duration_ms: Option<u64>,
    pub total_api_duration_ms: Option<u64>,
    pub total_lines_added: Option<u64>,
    pub total_lines_removed: Option<u64>,
}

impl Input {
    fn from_json_value(value: Value) -> Result<Self, serde_json::Error> {
        if let Some(hook_event_name) = value.get("hook_event_name").and_then(Value::as_str) {
            return match hook_event_name {
                "SessionStart" | "PostToolUse" | "UserPromptSubmit" | "Stop" => {
                    Ok(CodexHookInput::from_value(value)?.into_input())
                }
                _ => Ok(ClaudeInput::from_value(value)?.into_input()),
            };
        }

        if value.get("type").and_then(Value::as_str) == Some("agent-turn-complete") {
            return Ok(CodexNotifyInput::from_value(value)?.into_input());
        }

        Ok(ClaudeInput::from_value(value)?.into_input())
    }

    /// First non-empty path field, ignoring `Some("")` which Claude Code
    /// occasionally emits during early hook events. Codex hook payloads are
    /// normalized into the same fields so they follow the same fallback path.
    fn path_field(&self) -> Option<&str> {
        [self.workspace.current_dir.as_deref(), self.cwd.as_deref()]
            .into_iter()
            .flatten()
            .find(|s| !s.is_empty())
    }

    /// Path used as the cwd for VCS lookups (`workspace.current_dir` -> cwd
    /// -> process cwd). Substitutes the actual process cwd as a fallback so
    /// `gix::open` can resolve a real absolute path.
    pub fn vcs_dir(&self) -> String {
        if let Some(p) = self.path_field() {
            return p.to_string();
        }
        std::env::current_dir()
            .ok()
            .and_then(|p| p.to_str().map(str::to_owned))
            .unwrap_or_else(|| ".".to_string())
    }

    /// Display name for the directory segment (last path component).
    /// Falls back to the process cwd basename when Claude Code didn't
    /// supply a usable path - without this, fresh sessions render a bare
    /// `.` next to the VCS info.
    pub fn dir_name(&self) -> String {
        if let Some(p) = self.path_field() {
            return basename(p).to_string();
        }
        std::env::current_dir()
            .ok()
            .and_then(|p| {
                p.file_name()
                    .map(|n| n.to_string_lossy().into_owned())
                    .or_else(|| p.to_str().map(str::to_owned))
            })
            .unwrap_or_else(|| ".".to_string())
    }

    /// Full absolute path as Claude Code reported it. Falls back to the
    /// process cwd so fresh sessions still render something instead of
    /// a bare `.`.
    pub fn dir_full(&self) -> String {
        if let Some(p) = self.path_field() {
            return p.to_string();
        }
        std::env::current_dir()
            .ok()
            .and_then(|p| p.to_str().map(str::to_owned))
            .unwrap_or_else(|| ".".to_string())
    }

    /// Full path with the user's home directory collapsed to `~`.
    /// When the path doesn't live under home (or home isn't
    /// resolvable) we hand back the full form unchanged.
    pub fn dir_home(&self) -> String {
        let full = self.dir_full();
        let Some(home) = dirs::home_dir() else {
            return full;
        };
        let Some(home_str) = home.to_str() else {
            return full;
        };
        if home_str.is_empty() {
            return full;
        }
        if let Some(rest) = full.strip_prefix(home_str) {
            if rest.is_empty() {
                return "~".to_string();
            }
            // On Windows the separator is `\`, on Unix it's `/`. Match
            // either so the home collapse works on both without us
            // having to import `MAIN_SEPARATOR`.
            if rest.starts_with(['/', '\\']) {
                return format!("~{rest}");
            }
        }
        full
    }
}

fn basename(path: &str) -> &str {
    camino::Utf8Path::new(path).file_name().unwrap_or(".")
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
struct ClaudeInput {
    workspace: Workspace,
    cwd: Option<String>,
    transcript_path: Option<String>,
    session_id: Option<String>,
    model: Model,
    context_window: ContextWindow,
    rate_limits: RateLimits,
    cost: Cost,
}

impl ClaudeInput {
    fn from_value(value: Value) -> Result<Self, serde_json::Error> {
        serde_json::from_value(value)
    }

    fn into_input(self) -> Input {
        Input {
            workspace: self.workspace,
            cwd: self.cwd,
            transcript_path: self.transcript_path,
            session_id: self.session_id,
            model: self.model,
            context_window: self.context_window,
            rate_limits: self.rate_limits,
            cost: self.cost,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
struct CodexHookInput {
    session_id: Option<String>,
    transcript_path: Option<String>,
    cwd: Option<String>,
    model: Option<String>,
}

impl CodexHookInput {
    fn from_value(value: Value) -> Result<Self, serde_json::Error> {
        serde_json::from_value(value)
    }

    fn into_input(self) -> Input {
        let cwd = self.cwd.and_then(nonempty_owned);
        Input {
            workspace: Workspace {
                current_dir: cwd.clone(),
            },
            cwd,
            transcript_path: self.transcript_path.and_then(nonempty_owned),
            session_id: self.session_id.and_then(nonempty_owned),
            model: Model {
                display_name: self.model.and_then(nonempty_owned),
            },
            ..Input::default()
        }
    }
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
struct CodexNotifyInput {
    cwd: Option<String>,
    #[serde(rename = "thread-id")]
    thread_id: Option<String>,
}

impl CodexNotifyInput {
    fn from_value(value: Value) -> Result<Self, serde_json::Error> {
        serde_json::from_value(value)
    }

    fn into_input(self) -> Input {
        let cwd = self.cwd.and_then(nonempty_owned);
        Input {
            workspace: Workspace {
                current_dir: cwd.clone(),
            },
            cwd,
            session_id: self.thread_id.and_then(nonempty_owned),
            ..Input::default()
        }
    }
}

fn nonempty_owned(value: String) -> Option<String> {
    (!value.trim().is_empty()).then_some(value)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_claude_payload() {
        let input: Input = serde_json::from_str(
            r#"{
                "workspace": {"current_dir": "/tmp/claude"},
                "transcript_path": "/tmp/claude/session.jsonl",
                "session_id": "sess-1",
                "model": {"display_name": "Opus 4.1"},
                "context_window": {"used_percentage": 12.5}
            }"#,
        )
        .unwrap();

        assert_eq!(input.dir_full(), "/tmp/claude");
        assert_eq!(
            input.transcript_path.as_deref(),
            Some("/tmp/claude/session.jsonl")
        );
        assert_eq!(input.session_id.as_deref(), Some("sess-1"));
        assert_eq!(input.model.display_name.as_deref(), Some("Opus 4.1"));
        assert_eq!(input.context_window.used_percentage, Some(12.5));
    }

    #[test]
    fn parses_codex_session_start_hook_payload() {
        let input: Input = serde_json::from_str(
            r#"{
                "session_id": "thread-123",
                "transcript_path": "/tmp/codex/rollout.jsonl",
                "cwd": "/tmp/codex",
                "hook_event_name": "SessionStart",
                "model": "gpt-5-codex",
                "permission_mode": "default",
                "source": "startup"
            }"#,
        )
        .unwrap();

        assert_eq!(input.dir_full(), "/tmp/codex");
        assert_eq!(
            input.transcript_path.as_deref(),
            Some("/tmp/codex/rollout.jsonl")
        );
        assert_eq!(input.session_id.as_deref(), Some("thread-123"));
        assert_eq!(input.model.display_name.as_deref(), Some("gpt-5-codex"));
    }

    #[test]
    fn parses_codex_notify_payload() {
        let input: Input = serde_json::from_str(
            r#"{
                "type": "agent-turn-complete",
                "thread-id": "thread-456",
                "turn-id": "turn-1",
                "cwd": "/tmp/project",
                "input-messages": ["hello"],
                "last-assistant-message": "done"
            }"#,
        )
        .unwrap();

        assert_eq!(input.dir_full(), "/tmp/project");
        assert_eq!(input.session_id.as_deref(), Some("thread-456"));
        assert!(input.model.display_name.is_none());
    }
}
