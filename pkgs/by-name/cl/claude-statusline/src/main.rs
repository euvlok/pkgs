//! claude-statusline - fast Claude Code / Codex statusline rendered from a Rust
//! binary.
//!
//! Reads the Claude Code payload or supported Codex hook payloads as JSON,
//! gathers VCS info via `gix` (or `jj-lib` for jj repos), and prints a single
//! colored line. On any error or panic, falls back to printing just the
//! directory name so the statusline is never blank.

use std::fmt::Write as _;
use std::io::{self, Write as _};

use anstream::AutoStream;
use clap::{CommandFactory, FromArgMatches};
use clap_complete::Shell as ClapShell;

use claude_statusline::cli::{Cli, ColorChoice, HELP_AFTER_EXAMPLES, HELP_LAYOUT_SHAPES, Shell};
use claude_statusline::input::{Input, InputSource};
use claude_statusline::render::colors::Palette;
use claude_statusline::render::icons::{IconSet, Icons};
use claude_statusline::render::layout::Layout;
use claude_statusline::render::preview::{preview, preview_with};
use claude_statusline::render::render_with_pace;
use claude_statusline::settings::Settings;
use claude_statusline::theme::ThemeMode;
use claude_statusline::{config, theme};

fn main() {
    let cli = parse_cli();

    if let Some(shell) = cli.completions {
        emit_completions(shell);
        return;
    }

    let base_icons = cli.icons.icons();
    let icons: &'static Icons = match cli.separator.as_deref() {
        Some(sep) => {
            let mut owned = base_icons.clone();
            owned.sep = sep.to_string().leak();
            Box::leak(Box::new(owned))
        }
        None => base_icons,
    };

    let settings = cli.to_settings();
    let pace_settings = cli.to_pace_settings();

    // Detect terminal theme (dark/light) and build the color palette.
    // Skip OSC 11 entirely when colors are off — colorsaurus can otherwise
    // wait up to 100ms on terminals that don't reply, and the palette is
    // discarded by AutoStream anyway.
    let theme_mode = if matches!(cli.color, ColorChoice::Never) {
        ThemeMode::Dark
    } else {
        theme::detect(cli.theme)
    };
    let palette = Palette::for_theme(theme_mode);

    if cli.preview {
        let layout = config::load(cli.layout.as_deref(), cli.config.as_deref(), &cli.exclude);
        let line = preview(icons, &layout, &settings, &palette);
        let mut stdout = AutoStream::new(io::stdout().lock(), cli.color.into());
        let _ = writeln!(stdout, "layout: {layout}");
        let _ = stdout.write_all(line.as_bytes());
        let _ = stdout.write_all(b"\n");
        return;
    }

    std::panic::set_hook(Box::new(|_| {}));

    let result = std::panic::catch_unwind(|| {
        let input: Input = if let Some(json) = cli.input_json.as_deref() {
            serde_json::from_str(json).unwrap_or_default()
        } else {
            let stdin = io::stdin().lock();
            serde_json::from_reader(stdin).unwrap_or_default()
        };
        let default_layout = match input.source {
            InputSource::Claude => Layout::two_line(),
            InputSource::Codex => Layout::one_line(),
        };
        let layout = config::load_with_default(
            cli.layout.as_deref(),
            cli.config.as_deref(),
            &cli.exclude,
            default_layout,
        );
        render_with_pace(&input, icons, &layout, &settings, &pace_settings, &palette)
    });

    let line = result.unwrap_or_else(|_| fallback_dir());

    let mut stdout = AutoStream::new(io::stdout().lock(), cli.color.into());
    let _ = stdout.write_all(line.as_bytes());
}

fn parse_cli() -> Cli {
    // Scan args_os without allocating per-arg Strings. The dynamic
    // after_help block is expensive (renders preview shapes), so we only
    // build it when --help is actually present.
    let wants_help = std::env::args_os()
        .skip(1)
        .any(|a| a == "-h" || a == "--help");

    let mut cmd = Cli::command();
    if wants_help {
        cmd = cmd.after_help(dynamic_after_help());
    }

    // try_get_matches() reads std::env::args_os() internally — no need
    // to materialize a Vec<String> ourselves.
    match cmd.try_get_matches() {
        Ok(matches) => Cli::from_arg_matches(&matches).unwrap_or_else(|e| e.exit()),
        Err(e) => e.exit(),
    }
}

fn dynamic_after_help() -> String {
    const PREVIEW_WIDTH: usize = 100;

    let icons = IconSet::default().icons();
    let settings = Settings::default();
    let palette = Palette::dark();
    let mut out = String::from("Layout shapes (rendered with sample data):\n\n");
    for (label, dsl) in HELP_LAYOUT_SHAPES {
        let Ok(layout) = Layout::parse(dsl) else {
            continue;
        };
        let rendered = preview_with(icons, &layout, &settings, &palette, Some(PREVIEW_WIDTH));
        let _ = writeln!(out, "  {label}");
        let _ = writeln!(out, "    --layout '{dsl}'");
        for line in rendered.lines() {
            out.push_str("    ");
            out.push_str(line);
            out.push('\n');
        }
        out.push('\n');
    }
    out.push_str(HELP_AFTER_EXAMPLES);
    out
}

fn fallback_dir() -> String {
    std::env::current_dir()
        .ok()
        .and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()))
        .unwrap_or_else(|| ".".to_string())
}

fn emit_completions(shell: Shell) {
    let mut cmd = Cli::command();
    let bin = cmd.get_name().to_string();
    let mut out = io::stdout().lock();
    match shell {
        Shell::Bash => clap_complete::generate(ClapShell::Bash, &mut cmd, bin, &mut out),
        Shell::Zsh => clap_complete::generate(ClapShell::Zsh, &mut cmd, bin, &mut out),
        Shell::Fish => clap_complete::generate(ClapShell::Fish, &mut cmd, bin, &mut out),
        Shell::Elvish => clap_complete::generate(ClapShell::Elvish, &mut cmd, bin, &mut out),
        Shell::PowerShell => {
            clap_complete::generate(ClapShell::PowerShell, &mut cmd, bin, &mut out);
        }
        Shell::Nushell => {
            clap_complete::generate(clap_complete_nushell::Nushell, &mut cmd, bin, &mut out);
        }
    }
}
