//! Command-line interface definition.
//!
//! Help is deliberately terse: every flag's `help` is a single line, and
//! `long_help` is only set where the extra prose actually changes how
//! the user would invoke the flag. The global `long_about` carries the
//! segment cheatsheet so `--help` reads like a reference card instead
//! of a manpage.

use std::path::PathBuf;

use clap::{Args, Parser, ValueEnum};

use crate::pace::{PaceGlyphs, PaceSettings};
use crate::render::icons::IconSet;
use crate::render::layout::SegmentName;
use crate::settings::{ContextFormat, DirStyle, Settings};
use crate::theme::ThemeMode;

const LONG_ABOUT: &str = "\
Fast Claude Code / Codex statusline (gix + jj-lib).

Layout DSL:
  Comma `,` separates segments inside a line.
  Pipe  `|` (or a real newline in a config file) separates lines.
  The first segment of each line is its anchor and is never dropped.
  Pass `--preview` with any layout to see it rendered against sample data.";

/// Layout shapes embedded in `--help`.
///
/// Each entry is a `(label, dsl)` pair; `main` walks this list, runs
/// `preview_with` against each shape, and folds the rendered output
/// into the `after_help` block at runtime. Keeping the table here
/// (rather than inline in `main`) means the cli module owns the
/// user-facing strings end-to-end.
pub const HELP_LAYOUT_SHAPES: &[(&str, &str)] = &[
    ("one line", "dir,vcs,rates,context,model"),
    (
        "two line (default)",
        "dir,vcs,rates,context | model,diff,clock,cache",
    ),
    ("three line", "dir,vcs | rates,context | diff,model"),
    ("stacked", "dir | vcs | context"),
];

/// Trailer appended after the rendered shape examples in `--help`.
/// Kept as a const so it stays grep-able and we don't bury copy in
/// `main.rs`.
pub const HELP_AFTER_EXAMPLES: &str = "\
Other examples:
  claude-statusline --exclude rates < payload.json
  claude-statusline --input-json '{\"hook_event_name\":\"SessionStart\",\"cwd\":\"/tmp\",\"model\":\"gpt-5-codex\"}'
  claude-statusline --separator ' • ' --no-align
  claude-statusline --dir home --context-format percent
  claude-statusline --preview --layout 'dir,vcs,model | diff,context'
  claude-statusline --completions zsh > _claude-statusline

Config file (same DSL, `#` comments allowed):
  $XDG_CONFIG_HOME/claude-statusline/layout";

pub fn segment_help() -> String {
    use std::fmt::Write as _;

    let mut out = String::from("Segments:\n");
    for name in SegmentName::ALL {
        let spec = name.spec();
        let _ = write!(out, "  {:<12} {}", spec.name, spec.help);
        if !spec.aliases.is_empty() {
            let _ = write!(out, " (alias: {})", spec.aliases.join(", "));
        }
        out.push('\n');
    }
    out.push('\n');
    out
}

#[derive(Parser, Debug)]
#[command(
    version,
    about = "Fast Claude Code / Codex statusline (gix + jj-lib)",
    long_about = LONG_ABOUT,
    // `after_help` is set at runtime by `main` to include rendered
    // preview output (requires runtime icon detection).
    max_term_width = 100,
)]
pub struct Cli {
    #[command(flatten)]
    pub layout: LayoutArgs,

    #[command(flatten)]
    pub display: DisplayArgs,

    #[command(flatten)]
    pub shell: ShellArgs,

    #[command(flatten)]
    pub pace: PaceArgs,
}

#[derive(Args, Debug)]
#[command(next_help_heading = "Layout")]
pub struct LayoutArgs {
    /// Layout DSL: `dir,vcs,model | diff,context,rates`
    #[arg(
        short = 'l',
        long,
        env = "CLAUDE_STATUSLINE_LAYOUT",
        value_name = "DSL",
        hide_env = true
    )]
    pub layout: Option<String>,

    /// Drop named segments from the resolved layout
    #[arg(
        short = 'x',
        long,
        env = "CLAUDE_STATUSLINE_EXCLUDE",
        value_delimiter = ',',
        value_name = "NAMES",
        hide_env = true
    )]
    pub exclude: Vec<String>,

    /// Layout config file (defaults to
    /// $XDG_CONFIG_HOME/claude-statusline/layout)
    #[arg(
        short = 'c',
        long,
        env = "CLAUDE_STATUSLINE_CONFIG",
        value_name = "PATH",
        hide_env = true
    )]
    pub config: Option<PathBuf>,

    /// Disable cross-line column alignment (compact, ragged-right output)
    #[arg(
        long = "no-align",
        env = "CLAUDE_STATUSLINE_NO_ALIGN",
        hide_env = true,
        action = clap::ArgAction::SetTrue,
    )]
    pub no_align: bool,
}

#[derive(Args, Debug)]
#[command(next_help_heading = "Display")]
pub struct DisplayArgs {
    /// When to emit ANSI color escapes
    #[arg(
        long,
        value_enum,
        default_value_t = ColorChoice::Always,
        env = "CLAUDE_STATUSLINE_COLOR",
        hide_env = true,
    )]
    pub color: ColorChoice,

    /// Icon set (default: emoji)
    #[arg(
        short = 'i',
        long,
        value_enum,
        env = "CLAUDE_STATUSLINE_ICONS",
        value_name = "SET",
        default_value_t = IconSet::default(),
        hide_env = true,
        hide_default_value = true,
    )]
    pub icons: IconSet,

    /// Override the column separator glyph (default: ` │ `)
    #[arg(
        short = 's',
        long,
        env = "CLAUDE_STATUSLINE_SEPARATOR",
        value_name = "STR",
        hide_env = true
    )]
    pub separator: Option<String>,

    /// How the dir segment renders the cwd
    #[arg(
        long,
        value_enum,
        env = "CLAUDE_STATUSLINE_DIR",
        value_name = "STYLE",
        default_value_t = DirStyle::default(),
        hide_env = true,
        hide_default_value = true,
    )]
    pub dir: DirStyle,

    /// How the context segment formats usage
    #[arg(
        long = "context-format",
        value_enum,
        env = "CLAUDE_STATUSLINE_CONTEXT_FORMAT",
        value_name = "FMT",
        default_value_t = ContextFormat::default(),
        hide_env = true,
        hide_default_value = true,
    )]
    pub context_format: ContextFormat,

    /// Visibility floor for the 7-day rate-limit row, in percent
    #[arg(
        long = "seven-day-threshold",
        env = "CLAUDE_STATUSLINE_SEVEN_DAY_THRESHOLD",
        value_name = "PCT",
        default_value_t = 80,
        hide_env = true,
        hide_default_value = true
    )]
    pub seven_day_threshold: u32,

    /// Wrap the dir segment in an OSC 8 hyperlink (`auto` = on if stdout
    /// is a tty)
    #[arg(
        long,
        value_enum,
        env = "CLAUDE_STATUSLINE_HYPERLINKS",
        value_name = "MODE",
        default_value_t = HyperlinksMode::default(),
        hide_env = true,
        hide_default_value = true,
    )]
    pub hyperlinks: HyperlinksMode,

    /// Terminal theme for color adaptation [auto-detected when unset]
    #[arg(
        long,
        value_enum,
        env = "CLAUDE_STATUSLINE_THEME",
        value_name = "MODE",
        default_value_t = ThemeMode::default(),
        hide_env = true,
        hide_default_value = true,
    )]
    pub theme: ThemeMode,
}

#[derive(Args, Debug)]
#[command(next_help_heading = "Shell integration")]
pub struct ShellArgs {
    /// Print shell completions to stdout and exit
    #[arg(long, value_enum, value_name = "SHELL")]
    pub completions: Option<Shell>,

    /// Render the resolved layout against sample data and exit
    #[arg(long, action = clap::ArgAction::SetTrue)]
    pub preview: bool,

    /// Read the payload from a JSON string instead of stdin
    #[arg(long = "input-json", value_name = "JSON")]
    pub input_json: Option<String>,
}

#[derive(Args, Debug)]
#[command(next_help_heading = "Pace")]
pub struct PaceArgs {
    /// Pace segment glyph set (default: emoji)
    #[arg(
        long = "pace-glyphs",
        value_enum,
        env = "CLAUDE_STATUSLINE_PACE_GLYPHS",
        value_name = "SET",
        default_value_t = PaceGlyphs::default(),
        hide_env = true,
        hide_default_value = true,
    )]
    pub pace_glyphs: PaceGlyphs,

    /// Trailing wall-clock window (minutes) used to fit the pace rate
    #[arg(
        long = "pace-lookback-mins",
        env = "CLAUDE_STATUSLINE_PACE_LOOKBACK_MINS",
        value_name = "N",
        default_value_t = 20,
        hide_env = true,
        hide_default_value = true
    )]
    pub pace_lookback_mins: u32,

    /// Classify `cool` when `rate / fair_share` is below this ratio
    #[arg(
        long = "pace-cool-below",
        env = "CLAUDE_STATUSLINE_PACE_COOL_BELOW",
        value_name = "F",
        default_value_t = 0.9,
        hide_env = true,
        hide_default_value = true
    )]
    pub pace_cool_below: f64,

    /// Classify `too hot` when `rate / fair_share` is above this ratio
    #[arg(
        long = "pace-hot-above",
        env = "CLAUDE_STATUSLINE_PACE_HOT_ABOVE",
        value_name = "F",
        default_value_t = 1.2,
        hide_env = true,
        hide_default_value = true
    )]
    pub pace_hot_above: f64,

    /// Suppress pace projection for the first N minutes of a 5h window
    #[arg(
        long = "pace-warmup-mins",
        env = "CLAUDE_STATUSLINE_PACE_WARMUP_MINS",
        value_name = "N",
        default_value_t = 10,
        hide_env = true,
        hide_default_value = true
    )]
    pub pace_warmup_mins: u32,

    /// Emit pace internals to stderr on every render
    #[arg(
        long = "pace-debug",
        env = "CLAUDE_STATUSLINE_PACE_DEBUG",
        hide_env = true,
        action = clap::ArgAction::SetTrue,
    )]
    pub pace_debug: bool,
}

impl Cli {
    /// Collapse the parsed flags into the resolved [`Settings`] bundle
    /// the renderer consumes. Keeping this conversion here means
    /// `render()` never has to know about clap.
    pub const fn to_pace_settings(&self) -> PaceSettings {
        PaceSettings {
            lookback_mins: self.pace.pace_lookback_mins,
            cool_below: self.pace.pace_cool_below,
            hot_above: self.pace.pace_hot_above,
            warmup_mins: self.pace.pace_warmup_mins,
            glyphs: self.pace.pace_glyphs,
            debug: self.pace.pace_debug,
        }
    }

    pub fn to_settings(&self) -> Settings {
        use std::io::IsTerminal as _;
        let hyperlinks = match self.display.hyperlinks {
            HyperlinksMode::Always => true,
            HyperlinksMode::Never => false,
            HyperlinksMode::Auto => std::io::stdout().is_terminal(),
        };
        Settings {
            align: !self.layout.no_align,
            dir_style: self.display.dir,
            context_format: self.display.context_format,
            seven_day_threshold: self.display.seven_day_threshold,
            hyperlinks,
        }
    }
}

#[derive(Copy, Clone, Debug, ValueEnum, Default, Eq, PartialEq)]
#[value(rename_all = "lower")]
pub enum HyperlinksMode {
    /// On when stdout is a tty.
    #[default]
    Auto,
    /// Never emit OSC 8.
    Never,
    /// Always emit OSC 8.
    Always,
}

#[derive(Copy, Clone, Debug, ValueEnum)]
#[value(rename_all = "lower")]
pub enum ColorChoice {
    Auto,
    Always,
    Never,
}

impl From<ColorChoice> for anstream::ColorChoice {
    fn from(c: ColorChoice) -> Self {
        match c {
            ColorChoice::Auto => Self::Auto,
            ColorChoice::Always => Self::Always,
            ColorChoice::Never => Self::Never,
        }
    }
}

/// Target shell for `--completions`. Mirrors `clap_complete::Shell` but
/// adds Nushell (which lives in a separate crate) so we can expose all
/// the shells the user actually cares about behind one enum.
#[derive(Copy, Clone, Debug, ValueEnum)]
#[value(rename_all = "lower")]
pub enum Shell {
    Bash,
    Zsh,
    Fish,
    Nushell,
    Elvish,
    PowerShell,
}
