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

use claude_statusline::app;
use claude_statusline::cli::{Cli, HELP_AFTER_EXAMPLES, HELP_LAYOUT_SHAPES, Shell, segment_help};
use claude_statusline::render::colors::Palette;
use claude_statusline::render::icons::IconSet;
use claude_statusline::render::layout::Layout;
use claude_statusline::render::preview::preview_with;
use claude_statusline::settings::Settings;

fn main() {
    let cli = parse_cli();

    if let Some(shell) = cli.shell.completions {
        emit_completions(shell);
        return;
    }

    let icons = app::resolved_icons(cli.display.icons, cli.display.separator.as_deref());
    let settings = cli.to_settings();
    let pace_settings = cli.to_pace_settings();
    let palette = app::palette_for(cli.display.color, cli.display.theme);

    if cli.shell.preview {
        let preview = app::preview_output(&cli, icons.as_ref(), &settings, &palette);
        let mut stdout = AutoStream::new(io::stdout().lock(), cli.display.color.into());
        let _ = writeln!(stdout, "layout: {}", preview.layout);
        let _ = stdout.write_all(preview.line.as_bytes());
        let _ = stdout.write_all(b"\n");
        return;
    }

    std::panic::set_hook(Box::new(|_| {}));

    let result = std::panic::catch_unwind(|| {
        let input = app::parse_input(cli.shell.input_json.as_deref(), io::stdin().lock());
        app::render_statusline(
            &cli,
            &input,
            icons.as_ref(),
            &settings,
            &pace_settings,
            &palette,
        )
    });

    let line = result.unwrap_or_else(|_| app::fallback_dir());

    let mut stdout = AutoStream::new(io::stdout().lock(), cli.display.color.into());
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
    let mut out = segment_help();
    out.push_str("Layout shapes (rendered with sample data):\n\n");
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
