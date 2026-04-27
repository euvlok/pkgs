#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

//! Benchmarks for stdin payload deserialization. The renderer runs once
//! per Claude Code event, so parse cost shows up on every render.

use agent_statusline::input::Input;

fn main() {
    divan::main();
}

const CLAUDE_RICH: &str = r#"{
    "workspace": {"current_dir": "/tmp/example/projects/agent-statusline"},
    "transcript_path": "/tmp/example/.claude/projects/foo/sess.jsonl",
    "session_id": "sess-abcdef",
    "model": {"display_name": "Opus 4.6 (1M context)"},
    "context_window": {
        "used_percentage": 16.2,
        "context_window_size": 1000000,
        "current_usage": {
            "input_tokens": 162000,
            "output_tokens": 48000,
            "cache_creation_input_tokens": 0,
            "cache_read_input_tokens": 120000
        }
    },
    "rate_limits": {
        "five_hour": {"used_percentage": 13.0, "resets_at": 1700014400},
        "seven_day": {"used_percentage": 85.0, "resets_at": 1700518400}
    },
    "cost": {
        "total_duration_ms": 2340000,
        "total_api_duration_ms": 1260000,
        "total_lines_added": 1062,
        "total_lines_removed": 290
    }
}"#;

const CLAUDE_MINIMAL: &str = r#"{"workspace":{"current_dir":"/tmp/foo"}}"#;

const CODEX_HOOK: &str = r#"{
    "session_id": "thread-123",
    "transcript_path": "/tmp/codex/rollout.jsonl",
    "cwd": "/tmp/codex",
    "hook_event_name": "SessionStart",
    "model": "gpt-5-codex",
    "permission_mode": "default",
    "source": "startup"
}"#;

const CODEX_NOTIFY: &str = r#"{
    "type": "agent-turn-complete",
    "thread-id": "thread-456",
    "turn-id": "turn-1",
    "cwd": "/tmp/project",
    "input-messages": ["hello"],
    "last-assistant-message": "done"
}"#;

#[divan::bench]
fn parse_claude_rich() -> Input {
    serde_json::from_str(divan::black_box(CLAUDE_RICH)).unwrap()
}

#[divan::bench]
fn parse_claude_minimal() -> Input {
    serde_json::from_str(divan::black_box(CLAUDE_MINIMAL)).unwrap()
}

#[divan::bench]
fn parse_codex_hook() -> Input {
    serde_json::from_str(divan::black_box(CODEX_HOOK)).unwrap()
}

#[divan::bench]
fn parse_codex_notify() -> Input {
    serde_json::from_str(divan::black_box(CODEX_NOTIFY)).unwrap()
}
