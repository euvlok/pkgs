#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::io::Write as _;
use std::process::Command;

const fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_agent-statusline")
}

fn write_config(text: &str) -> tempfile::NamedTempFile {
    let mut file = tempfile::NamedTempFile::new().unwrap();
    file.write_all(text.as_bytes()).unwrap();
    file
}

fn run(args: &[&str]) -> std::process::Output {
    Command::new(bin()).args(args).output().unwrap()
}

#[test]
fn schema_emits_valid_json() {
    let output = run(&["--schema"]);
    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["title"], "AgentStatuslineConfig");
    assert_eq!(json["type"], "object");
}

#[test]
fn defaults_format_json_emits_valid_config() {
    let output = run(&["--defaults", "--format", "json"]);
    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["version"], 1);
    assert!(json["segments"]["dir"].is_object());
}

#[test]
fn capabilities_include_builtin_segment_types() {
    let output = run(&["--capabilities"]);
    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let segments = json["segments"].as_array().unwrap();
    for ty in [
        "dir",
        "vcs",
        "model",
        "diff",
        "context",
        "rate-limits",
        "clock",
        "speed",
        "cache",
        "pace",
        "env",
        "template",
    ] {
        assert!(
            segments.iter().any(|segment| segment["type"] == ty),
            "missing {ty}"
        );
    }
}

#[test]
fn format_json_includes_text_and_structured_segments() {
    let config = write_config(
        r#"
version = 1

[display]
format = "json"
icons = "text"

[statusline]
lines = [["dir", "changes"]]

[segments.dir]
type = "dir"

[segments.changes]
type = "diff"
"#,
    );
    let output = Command::new(bin())
        .arg("--config")
        .arg(config.path())
        .arg("--input-json")
        .arg(r#"{"workspace":{"current_dir":"/tmp/myapp"},"cost":{"total_lines_added":4,"total_lines_removed":1}}"#)
        .output()
        .unwrap();
    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert!(json["text"].as_str().unwrap().contains("myapp"));
    assert_eq!(json["lines"][0]["segments"][0]["id"], "dir");
    assert_eq!(json["lines"][0]["segments"][1]["type"], "diff");
}

#[test]
fn inspect_includes_resolved_segments_and_warnings() {
    let config = write_config(
        r#"
version = 1

[statusline]
lines = [["dir", "missing"]]

[segments.dir]
type = "dir"
"#,
    );
    let output = Command::new(bin())
        .arg("--inspect")
        .arg("--config")
        .arg(config.path())
        .arg("--input-json")
        .arg(r#"{"workspace":{"current_dir":"/tmp/myapp"}}"#)
        .output()
        .unwrap();
    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(json["resolved"]["lines"][0][0], "dir");
    assert_eq!(json["segments"][0]["id"], "dir");
    assert!(
        json["warnings"][0]["message"]
            .as_str()
            .unwrap()
            .contains("missing")
    );
}

#[test]
fn env_segment_renders_and_hides_empty_values() {
    let config = write_config(
        r##"
version = 1

[display]
format = "json"

[statusline]
lines = [["ticket", "empty"]]

[segments.ticket]
type = "env"
key = "TICKET"
prefix = "#"
hide_empty = true

[segments.empty]
type = "env"
key = "EMPTY_TICKET"
hide_empty = true
"##,
    );
    let output = Command::new(bin())
        .arg("--config")
        .arg(config.path())
        .env("TICKET", "123")
        .env("EMPTY_TICKET", "")
        .output()
        .unwrap();
    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let segments = json["lines"][0]["segments"].as_array().unwrap();
    assert_eq!(segments.len(), 1);
    assert_eq!(segments[0]["plain"], "#123");
}

#[test]
fn template_segment_renders_input_fields() {
    let config = write_config(
        r#"
version = 1

[display]
format = "json"

[statusline]
lines = [["workspace"]]

[segments.workspace]
type = "template"
template = "{source}:{session_id}:{model}:{cwd}"
"#,
    );
    let output = Command::new(bin())
        .arg("--config")
        .arg(config.path())
        .arg("--input-json")
        .arg(
            r#"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/tmp/proj","model":"gpt-5-codex"}"#,
        )
        .output()
        .unwrap();
    assert!(output.status.success());
    let json: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(
        json["lines"][0]["segments"][0]["plain"],
        "codex:s1:gpt-5-codex:/tmp/proj"
    );
}

#[test]
fn invalid_toml_falls_back_during_normal_render() {
    let config = write_config("not = [valid");
    let output = Command::new(bin())
        .arg("--config")
        .arg(config.path())
        .arg("--input-json")
        .arg(r#"{"workspace":{"current_dir":"/tmp/myapp"}}"#)
        .output()
        .unwrap();
    assert!(output.status.success());
    assert!(!String::from_utf8_lossy(&output.stdout).trim().is_empty());
}

#[test]
fn invalid_toml_fails_inspect() {
    let config = write_config("not = [valid");
    let output = Command::new(bin())
        .arg("--inspect")
        .arg("--config")
        .arg(config.path())
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("failed to parse config"));
}
