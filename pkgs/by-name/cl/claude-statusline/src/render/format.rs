//! Pure formatting helpers (token humanization, model-name shortening).

/// Humanize a token count: `1_234_567` -> `"1.2M"`, `34_500` -> `"34k"`,
/// small values -> bare integer. Mirrors the jq `humanize` def in the bash
/// script.
#[must_use]
pub fn humanize_tokens(n: u64) -> String {
    match n {
        0 => String::new(),
        // 950_000+ rounds up to "1.0M", not "950k": picking the bucket
        // *after* rounding keeps the boundary visually consistent.
        950_000.. => {
            let tenths = (n + 50_000) / 100_000;
            format!("{}.{}M", tenths / 10, tenths % 10)
        }
        1_000.. => format!("{}k", n / 1_000),
        _ => n.to_string(),
    }
}

/// Compact human-friendly duration.
///
/// `45` -> `"45s"`, `750` -> `"12m"`, `5000` -> `"1h 23m"`,
/// `300_000` -> `"3d 11h"`. Returns the empty string for zero or
/// negative input so callers can drop the segment cleanly.
#[must_use]
pub fn humanize_duration(secs: i64) -> String {
    if secs <= 0 {
        return String::new();
    }
    let secs = secs as u64;
    match secs {
        0..60 => format!("{secs}s"),
        60..3600 => format!("{}m", secs / 60),
        3600..86400 => {
            let h = secs / 3600;
            let m = (secs % 3600) / 60;
            match m {
                0 => format!("{h}h"),
                _ => format!("{h}h {m}m"),
            }
        }
        _ => {
            let d = secs / 86400;
            let h = (secs % 86400) / 3600;
            match h {
                0 => format!("{d}d"),
                _ => format!("{d}d {h}h"),
            }
        }
    }
}

/// Shorten the model display name to its family: `"Opus 4.6 (1M context)"`
/// -> `"Opus"`, `"Sonnet 4.5"` -> `"Sonnet"`, `"Haiku 4.5"` -> `"Haiku"`.
///
/// For ChatGPT models, strip the `gpt` prefix and return only the
/// leading version number: `"GPT 5.4"` -> `"5.4"`, `"gpt-5"` -> `"5"`.
#[must_use]
pub fn shorten_model(name: &str) -> &str {
    let trimmed = name.trim_start();
    if trimmed.len() >= 3 && trimmed.as_bytes()[..3].eq_ignore_ascii_case(b"gpt") {
        let rest = trimmed[3..].trim_start_matches([' ', '-', '_']);
        let end = rest
            .as_bytes()
            .iter()
            .position(|&b| !(b.is_ascii_digit() || b == b'.'))
            .unwrap_or(rest.len());
        let head = &rest[..end];
        if !head.is_empty() {
            return head;
        }
        return rest.trim_end();
    }
    match trimmed.as_bytes().first() {
        Some(b'O') => "Opus",
        Some(b'S') => "Sonnet",
        Some(b'H') => "Haiku",
        // Unknown family: hand the trimmed name back so we don't blank
        // out the segment for a model we haven't taught the dispatch
        // about yet. Trailing whitespace is harmless inside a segment.
        _ => trimmed.trim_end(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn humanize() {
        assert_eq!(humanize_tokens(0), "");
        assert_eq!(humanize_tokens(123), "123");
        assert_eq!(humanize_tokens(34_500), "34k");
        assert_eq!(humanize_tokens(949_999), "949k");
        assert_eq!(humanize_tokens(950_000), "1.0M");
        assert_eq!(humanize_tokens(1_234_567), "1.2M");
        assert_eq!(humanize_tokens(1_500_000), "1.5M");
    }

    #[test]
    fn humanize_duration_buckets() {
        assert_eq!(humanize_duration(0), "");
        assert_eq!(humanize_duration(-5), "");
        assert_eq!(humanize_duration(45), "45s");
        assert_eq!(humanize_duration(750), "12m");
        assert_eq!(humanize_duration(5000), "1h 23m");
        assert_eq!(humanize_duration(7200), "2h");
        assert_eq!(humanize_duration(90_000), "1d 1h");
        assert_eq!(humanize_duration(86_400), "1d");
    }

    #[test]
    fn model_shortening() {
        assert_eq!(shorten_model("Opus 4.6 (1M context)"), "Opus");
        assert_eq!(shorten_model("Sonnet 4.6"), "Sonnet");
        assert_eq!(shorten_model("Sonnet 4.6 (1M context)"), "Sonnet");
        assert_eq!(shorten_model("Haiku 4.5"), "Haiku");
        assert_eq!(shorten_model("Haiku"), "Haiku");
        // ChatGPT family: only the version number.
        assert_eq!(shorten_model("GPT 5.4"), "5.4");
        assert_eq!(shorten_model("gpt 5.5"), "5.5");
        assert_eq!(shorten_model("gpt-5"), "5");
        assert_eq!(shorten_model("gpt-5-codex"), "5");
        // Unknown family: hand the (trimmed) name back unchanged.
        assert_eq!(shorten_model("Mystery 9.0"), "Mystery 9.0");
    }
}
