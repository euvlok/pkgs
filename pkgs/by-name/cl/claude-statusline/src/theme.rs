//! Terminal theme detection: dark vs light background.
//!
//! Detection strategy (in priority order):
//!
//! 1. **CLI override** (`--theme dark` / `--theme light`) – instant, no I/O.
//! 2. **`$COLORFGBG`** – cheap env-var hint set by some terminals.
//! 3. **OSC 11 query** via `terminal-colorsaurus` – query the terminal and
//!    parse its response. Adds ~5–50 ms of latency; works in any terminal
//!    that speaks the protocol (including modern Windows Terminal, with an
//!    SSH-aware timeout).
//! 4. **Default** – dark.

use std::time::Duration;

use clap::ValueEnum;

/// Dark or light terminal background.
#[derive(Copy, Clone, Debug, Eq, PartialEq, ValueEnum, Default)]
#[value(rename_all = "lower")]
pub enum ThemeMode {
    /// Auto-detect via `$COLORFGBG` then OSC 11.
    #[default]
    Auto,
    /// Force dark palette.
    Dark,
    /// Force light palette.
    Light,
}

/// Resolve the effective theme. `cli_override` is the raw `--theme` value;
/// `Auto` triggers detection, `Dark`/`Light` short-circuit immediately.
pub fn detect(cli_override: ThemeMode) -> ThemeMode {
    match cli_override {
        ThemeMode::Dark | ThemeMode::Light => cli_override,
        ThemeMode::Auto => detect_auto(),
    }
}

fn detect_auto() -> ThemeMode {
    if let Some(mode) = detect_from_colorfgbg() {
        return mode;
    }
    if let Some(mode) = detect_from_osc() {
        return mode;
    }
    ThemeMode::Dark
}

/// `COLORFGBG=<fg>;<bg>`: classify by the background ANSI palette index.
/// Indices 0–6 and 8 are dark; 7 and 9–15 are light.
fn detect_from_colorfgbg() -> Option<ThemeMode> {
    let value = std::env::var("COLORFGBG").ok()?;
    let bg_str = value.split(';').nth(1)?.trim();
    let bg: u8 = bg_str.parse().ok()?;
    Some(match bg {
        0..=6 | 8 => ThemeMode::Dark,
        _ => ThemeMode::Light,
    })
}

fn detect_from_osc() -> Option<ThemeMode> {
    let mut opts = terminal_colorsaurus::QueryOptions::default();
    opts.timeout = Duration::from_millis(100);
    match terminal_colorsaurus::theme_mode(opts) {
        Ok(terminal_colorsaurus::ThemeMode::Dark) => Some(ThemeMode::Dark),
        Ok(terminal_colorsaurus::ThemeMode::Light) => Some(ThemeMode::Light),
        Err(_) => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cli_override_short_circuits() {
        assert_eq!(detect(ThemeMode::Dark), ThemeMode::Dark);
        assert_eq!(detect(ThemeMode::Light), ThemeMode::Light);
    }
}
