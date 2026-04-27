//! Cold-start benchmarks: spawn the release binary and measure end-to-end
//! wall time. Claude Code re-execs the statusline on every render, so this
//! is the metric that actually matters in production.
//!
//! Each bench shells out to the binary built by Cargo (located via
//! `CARGO_BIN_EXE_claude-statusline`) and feeds it a fixed payload. Numbers
//! include process spawn, dyld linking, clap parsing, JSON parsing, render,
//! and stdout flush.

use std::process::{Command, Stdio};

fn main() {
    divan::main();
}

const BIN: &str = env!("CARGO_BIN_EXE_claude-statusline");

const PAYLOAD: &str = r#"{
  "workspace": {"current_dir": "/tmp/example/projects/claude-statusline"},
  "model": {"display_name": "Opus 4.6 (1M context)"},
  "context_window": {
    "used_percentage": 2.5,
    "context_window_size": 1000000,
    "current_usage": {
      "input_tokens": 25000,
      "output_tokens": 8000,
      "cache_read_input_tokens": 300000,
      "cache_creation_input_tokens": 50000
    }
  },
  "cost": {"total_cost_usd": 1.23, "total_lines_added": 120, "total_lines_removed": 40},
  "rate_limits": {"five_hour": {"used_percentage": 12.0, "resets_in_seconds": 900}}
}"#;

/// Process spawn + immediate exit. Establishes the OS/dyld floor that every
/// other bench in this file inherits.
#[divan::bench]
fn spawn_version() {
    let status = Command::new(BIN)
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .expect("spawn cs --version");
    assert!(status.success());
}

/// Spawn + clap parse + empty-input render path. Excludes JSON parsing of a
/// real payload but exercises the full main() flow.
#[divan::bench]
fn spawn_empty_input() {
    let status = Command::new(BIN)
        .args(["--input-json", "{}", "--color", "never"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .expect("spawn cs empty");
    assert!(status.success());
}

/// Spawn + full pipeline with a representative Claude Code payload. This is
/// the closest single-shot proxy for what users actually pay on every
/// statusline refresh.
#[divan::bench]
fn spawn_full_payload() {
    let status = Command::new(BIN)
        .args(["--input-json", PAYLOAD, "--color", "never"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .expect("spawn cs full");
    assert!(status.success());
}

/// Same payload, but force a layout DSL through the parser as well — closer
/// to a configured user invocation.
#[divan::bench]
fn spawn_full_payload_with_layout() {
    let status = Command::new(BIN)
        .args([
            "--input-json",
            PAYLOAD,
            "--color",
            "never",
            "--layout",
            "dir vcs | model context cost",
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .expect("spawn cs layout");
    assert!(status.success());
}
