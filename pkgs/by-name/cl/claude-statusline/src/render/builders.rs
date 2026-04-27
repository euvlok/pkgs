//! Per-segment builders. Each function returns an `Option<Segment>` of
//! styled cells; passing `None` upstream tells the layout to skip the
//! position cleanly.

use std::path::Path;

use crate::input::{Input, RateLimit};
use crate::pace::{self, PaceSettings};
use crate::render::colors::Palette;
use crate::render::format::{humanize_duration, humanize_tokens, shorten_model};
use crate::render::icons::Icons;
use crate::render::segment::{Cell, Segment};
use crate::settings::{ContextFormat, DirStyle, Settings};

pub fn dir(input: &Input, settings: &Settings) -> Segment {
    let mut s = Segment::anchor();
    let text = match settings.dir_style {
        DirStyle::Basename => input.dir_name(),
        DirStyle::Full => input.dir_full(),
        DirStyle::Home => input.dir_home(),
    };
    match (settings.hyperlinks, input.workspace.current_dir.as_deref()) {
        (true, Some(full_path)) => match file_url(full_path) {
            Some(url) => {
                s.push_linked(text, anstyle::Style::new(), url);
            }
            None => {
                s.push_plain(text);
            }
        },
        _ => {
            s.push_plain(text);
        }
    }
    s
}

fn file_url(path: &str) -> Option<String> {
    anstyle_hyperlink::file_to_url(None, Path::new(path))
}

pub fn model(input: &Input, _icons: &Icons, pal: &Palette) -> Option<Segment> {
    let name = input.model.display_name.as_deref()?;
    let short = shorten_model(name);
    if short.is_empty() {
        return None;
    }
    let mut s = Segment::droppable();
    s.push_styled(short, pal.blue);
    Some(s)
}

pub fn diff(input: &Input, pal: &Palette) -> Option<Segment> {
    let added = input.cost.total_lines_added.unwrap_or(0);
    let removed = input.cost.total_lines_removed.unwrap_or(0);
    if added == 0 && removed == 0 {
        return None;
    }
    let mut s = Segment::droppable();
    s.push_styled(format!("+{added}"), pal.green);
    s.push_plain(" ");
    s.push_styled(format!("-{removed}"), pal.red);
    Some(s)
}

pub fn context(input: &Input, settings: &Settings, pal: &Palette) -> Option<Segment> {
    let used = input.context_window.used_percentage?;
    let pct = used.round() as i64;
    if pct < 0 {
        return None;
    }
    let pct = pct as u32;
    let cur_tokens = input.context_window.current_usage.total();
    let max_tokens = input.context_window.context_window_size.unwrap_or(0);
    let have_tokens = cur_tokens > 0 && max_tokens > 0;
    let style = if have_tokens {
        pal.color_for_token_count(cur_tokens)
    } else {
        pal.color_for_pct(pct, 50, 75)
    };

    let text = match (have_tokens, settings.context_format) {
        (true, ContextFormat::Auto | ContextFormat::Tokens) => {
            format!(
                "{}/{}",
                humanize_tokens(cur_tokens),
                humanize_tokens(max_tokens)
            )
        }
        _ => format!("{pct}%"),
    };
    let mut s = Segment::droppable();
    s.push_styled(text, style);
    let out_tokens = input.context_window.current_usage.output_tokens;
    if out_tokens > 0 {
        // Snapshot the essentials before tacking on the `(N out)` tail,
        // so the fit pass can fall back to the compact form on narrow
        // terminals instead of dropping the segment outright.
        s.mark_compact();
        s.push_styled(format!(" ({} out)", humanize_tokens(out_tokens)), pal.dim);
    }
    Some(s)
}

pub fn clock(input: &Input, icons: &Icons, pal: &Palette) -> Option<Segment> {
    let ms = input.cost.total_duration_ms?;
    if ms == 0 {
        return None;
    }
    #[expect(clippy::cast_possible_wrap)]
    let dur = humanize_duration((ms / 1000) as i64);
    if dur.is_empty() {
        return None;
    }
    let mut s = Segment::droppable();
    if !icons.clock.is_empty() {
        s.push_plain(format!("{} ", icons.clock));
    }
    s.push_styled(&dur, pal.dim);
    if let Some(api_ms) = input.cost.total_api_duration_ms
        && api_ms > 0
    {
        #[expect(clippy::cast_possible_wrap)]
        let wait = humanize_duration((api_ms / 1000) as i64);
        if !wait.is_empty() && wait != dur {
            s.mark_compact();
            s.push_styled(format!(" (chat {wait})"), pal.dim);
        }
    }
    Some(s)
}

pub fn speed(input: &Input, pal: &Palette) -> Option<Segment> {
    let api_ms = input.cost.total_api_duration_ms.filter(|&ms| ms > 0)?;
    let tokens = input.context_window.current_usage.output_tokens;
    if tokens == 0 {
        return None;
    }
    let secs = api_ms as f64 / 1000.0;
    let tps = tokens as f64 / secs;
    let mut s = Segment::droppable();
    let text = match tps {
        t if t >= 1000.0 => format!("{:.1}k tok/s", t / 1000.0),
        _ => format!("{tps:.0} tok/s"),
    };
    s.push_styled(text, pal.cyan);
    Some(s)
}

pub fn cache(input: &Input, pal: &Palette) -> Option<Segment> {
    let pct = input
        .context_window
        .current_usage
        .cache_hit_pct()
        .filter(|&p| p > 0)?;
    let style = match pct {
        70.. => pal.green,
        40.. => pal.yellow,
        _ => pal.red,
    };
    let mut s = Segment::droppable();
    s.push_styled(format!("cache {pct}%"), style);
    Some(s)
}

pub fn pace(
    input: &Input,
    settings: &PaceSettings,
    pal: &Palette,
    now_unix: u64,
) -> Option<Segment> {
    pace::pace(input, settings, pal, now_unix)
}

/// Resolve a rate-limit slot to `(pct, reset_unix)` if its used % is
/// non-negative and meets `floor`. Centralises the i64-cast / threshold
/// dance so `rate_limits` can stay flat.
fn visible_pct(slot: &RateLimit, floor: u32) -> Option<u32> {
    let pct = slot.used_percentage?.round();
    if pct < 0.0 {
        return None;
    }
    let pct = pct as u32;
    (pct >= floor).then_some(pct)
}

pub fn rate_limits(
    input: &Input,
    icons: &Icons,
    settings: &Settings,
    pal: &Palette,
    now_unix: u64,
) -> Option<Segment> {
    #[expect(clippy::cast_possible_wrap)]
    let now = Some(now_unix as i64);

    let rl = &input.rate_limits;
    // (label, slot, pct, show_countdown). 7d is suppressed below the
    // configured threshold; 5h always shows.
    let visible = [
        ("5h", &rl.five_hour, visible_pct(&rl.five_hour, 0), true),
        (
            "7d",
            &rl.seven_day,
            visible_pct(&rl.seven_day, settings.seven_day_threshold),
            false,
        ),
    ];
    let mut visible = visible
        .into_iter()
        .filter_map(|(l, s, pct, c)| pct.map(|p| (l, s, p, c)))
        .peekable();
    visible.peek()?;

    let mut s = Segment::droppable();
    let mut compact: Vec<Cell> = Vec::new();
    let mut any_countdown = false;
    let mut both = |s: &mut Segment, cell: Cell| {
        compact.push(cell.clone());
        s.cells.push(cell);
    };
    if !icons.clock.is_empty() {
        both(&mut s, Cell::plain(format!("{} ", icons.clock)));
    }
    for (i, (label, slot, pct, show_countdown)) in visible.enumerate() {
        if i > 0 {
            both(&mut s, Cell::plain("  "));
        }
        both(&mut s, Cell::new(label, pal.dim));
        both(&mut s, Cell::plain(" "));
        both(
            &mut s,
            Cell::new(format!("{pct}%"), pal.color_for_pct(pct, 50, 100)),
        );
        if show_countdown
            && let (Some(now), Some(reset)) = (now, slot.resets_at)
            && reset - now > 0
        {
            s.push_plain(" ");
            s.push_styled(humanize_duration(reset - now), pal.dim);
            any_countdown = true;
        }
    }
    if any_countdown {
        s.set_compact(compact);
    }
    Some(s)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_urls_percent_encode_reserved_and_control_bytes() {
        assert_eq!(
            file_url("/tmp/a b#c%\n").as_deref(),
            Some("file:///tmp/a%20b%23c%25%0A")
        );
    }

    #[test]
    fn file_urls_add_slash_for_relative_paths() {
        assert_eq!(
            file_url("tmp/project").as_deref(),
            Some("file:///tmp/project")
        );
    }
}
