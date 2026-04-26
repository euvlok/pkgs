//! Serde structs for the Claude Code / Codex input payload.
//!
//! Claude Code streams a rich status payload on stdin; Codex exposes several
//! smaller JSON hook payloads instead. We normalize both into one lenient
//! `Input` so the renderer can stay provider-agnostic and simply omit segments
//! whose backing data is unavailable.

use serde::Deserialize;
use serde::Deserializer;

#[derive(Debug, Default)]
pub struct Input {
    pub source: InputSource,
    pub workspace: Workspace,
    pub cwd: Option<String>,
    pub transcript_path: Option<String>,
    pub session_id: Option<String>,
    pub model: Model,
    pub context_window: ContextWindow,
    pub rate_limits: RateLimits,
    pub cost: Cost,
}

#[derive(Copy, Clone, Debug, Default, Eq, PartialEq)]
pub enum InputSource {
    #[default]
    Claude,
    Codex,
}

impl<'de> Deserialize<'de> for Input {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        Ok(RawInput::deserialize(deserializer)?.into())
    }
}

#[derive(Deserialize)]
#[serde(untagged)]
enum RawInput {
    // CodexHookInput requires a known `hook_event_name`, so it only matches
    // Codex hook payloads.
    CodexHook(CodexHookInput),
    // CodexNotifyInput requires `type: "agent-turn-complete"`.
    CodexNotify(CodexNotifyInput),
    // Fallback: Claude Code's rich status payload (all fields optional).
    Claude(ClaudeInput),
}

impl From<RawInput> for Input {
    fn from(raw: RawInput) -> Self {
        match raw {
            RawInput::CodexHook(v) => v.into(),
            RawInput::CodexNotify(v) => v.into(),
            RawInput::Claude(v) => v.into(),
        }
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

impl From<ClaudeInput> for Input {
    fn from(v: ClaudeInput) -> Self {
        Self {
            source: InputSource::Claude,
            workspace: v.workspace,
            cwd: v.cwd,
            transcript_path: v.transcript_path,
            session_id: v.session_id,
            model: v.model,
            context_window: v.context_window,
            rate_limits: v.rate_limits,
            cost: v.cost,
        }
    }
}

#[derive(Deserialize)]
#[allow(dead_code)] // variants used as untagged tag values
enum CodexHookEvent {
    SessionStart,
    PostToolUse,
    UserPromptSubmit,
    Stop,
}

#[derive(Deserialize)]
struct CodexHookInput {
    // Required so untagged dispatch only matches recognized Codex hooks.
    #[serde(rename = "hook_event_name")]
    _hook_event_name: CodexHookEvent,
    #[serde(default)]
    session_id: Option<String>,
    #[serde(default)]
    transcript_path: Option<String>,
    #[serde(default)]
    cwd: Option<String>,
    #[serde(default)]
    model: Option<String>,
}

impl From<CodexHookInput> for Input {
    fn from(v: CodexHookInput) -> Self {
        let cwd = v.cwd.and_then(nonempty_owned);
        Self {
            source: InputSource::Codex,
            workspace: Workspace {
                current_dir: cwd.clone(),
            },
            cwd,
            transcript_path: v.transcript_path.and_then(nonempty_owned),
            session_id: v.session_id.and_then(nonempty_owned),
            model: Model {
                display_name: v.model.and_then(nonempty_owned),
            },
            ..Self::default()
        }
    }
}

#[derive(Deserialize)]
#[allow(dead_code)]
enum CodexNotifyKind {
    #[serde(rename = "agent-turn-complete")]
    AgentTurnComplete,
}

#[derive(Deserialize)]
struct CodexNotifyInput {
    #[serde(rename = "type")]
    _kind: CodexNotifyKind,
    #[serde(default)]
    cwd: Option<String>,
    #[serde(default, rename = "thread-id")]
    thread_id: Option<String>,
}

impl From<CodexNotifyInput> for Input {
    fn from(v: CodexNotifyInput) -> Self {
        let cwd = v.cwd.and_then(nonempty_owned);
        Self {
            source: InputSource::Codex,
            workspace: Workspace {
                current_dir: cwd.clone(),
            },
            cwd,
            session_id: v.thread_id.and_then(nonempty_owned),
            ..Self::default()
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
        assert_eq!(input.source, InputSource::Claude);
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
        assert_eq!(input.source, InputSource::Codex);
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
        assert_eq!(input.source, InputSource::Codex);
    }
}
