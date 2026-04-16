//! User-configurable layout: which segments appear, on which line, in
//! which order. The layout is a `Vec<Vec<SegmentName>>` (lines of named
//! segments), parsed from a tiny DSL or loaded from a config file.
//!
//! DSL syntax:
//!
//! ```text
//! dir,vcs,model | cost,diff,context,rate_limits
//! ```
//!
//! - `|` separates lines (use `\n` in config files for readability).
//! - `,` separates segments inside a line.
//! - Whitespace is ignored.
//! - Unknown segment names are an error so typos surface immediately.
//!
//! The first segment of each line is the line's *anchor*: it is never
//! dropped, even when the terminal is too narrow. Every other segment
//! is droppable from the right.

use std::fmt;
use std::str::FromStr;

use strum::EnumString;

use crate::input::Input;
use crate::pace::PaceSettings;
use crate::render::builders;
use crate::render::colors::Palette;
use crate::render::segment::Segment;
use crate::session::Deltas;
use crate::settings::Settings;

/// Names of every renderable segment. Add a variant here, wire it in
/// [`SegmentName::build`], and add `strum` annotations for any aliases,
/// and it instantly becomes available in the layout DSL.
///
/// `strum::Display` emits the canonical name (the `to_string` value);
/// `strum::EnumString` accepts both the canonical name and any aliases
/// listed in `serialize`.
#[derive(Copy, Clone, Debug, Eq, PartialEq, Hash, strum::Display, EnumString)]
pub enum SegmentName {
    #[strum(to_string = "dir")]
    Dir,
    #[strum(to_string = "vcs", serialize = "git", serialize = "jj")]
    Vcs,
    #[strum(to_string = "model")]
    Model,
    #[strum(to_string = "cost")]
    Cost,
    #[strum(to_string = "diff", serialize = "lines")]
    Diff,
    #[strum(to_string = "context", serialize = "ctx")]
    Context,
    #[strum(
        to_string = "rate_limits",
        serialize = "rate-limits",
        serialize = "rates",
        serialize = "limits"
    )]
    RateLimits,
    #[strum(to_string = "clock", serialize = "time", serialize = "elapsed")]
    Clock,
    #[strum(to_string = "speed", serialize = "tps", serialize = "throughput")]
    Speed,
    #[strum(to_string = "cache")]
    Cache,
    #[strum(to_string = "pace", serialize = "burn")]
    Pace,
}

impl SegmentName {
    /// Parse a segment name from user input (trimmed). Returns `None`
    /// for unrecognised names.
    #[must_use]
    pub fn parse(s: &str) -> Option<Self> {
        Self::from_str(s.trim()).ok()
    }

    /// Build the styled [`Segment`] for this name. Returns `None` when
    /// the underlying data is missing - the renderer drops the line
    /// position cleanly.
    pub fn build(self, ctx: &BuildCtx<'_>) -> Option<Segment> {
        let pal = ctx.palette;
        match self {
            Self::Dir => Some(builders::dir(ctx.input, ctx.settings)),
            Self::Vcs => ctx.vcs.clone(),
            Self::Model => builders::model(ctx.input, ctx.icons, pal),
            Self::Cost => builders::cost(ctx.input, ctx.cost_usd, &ctx.deltas, ctx.settings, pal),
            Self::Diff => builders::diff(ctx.input, &ctx.deltas, ctx.settings, pal),
            Self::Context => builders::context(ctx.input, &ctx.deltas, ctx.settings, pal),
            Self::RateLimits => builders::rate_limits(ctx.input, ctx.icons, ctx.settings, pal),
            Self::Clock => builders::clock(ctx.input, ctx.icons, pal),
            Self::Speed => builders::speed(ctx.input, pal),
            Self::Cache => builders::cache(ctx.input, pal),
            Self::Pace => builders::pace(ctx.input, ctx.pace_settings, pal),
        }
    }
}

/// Bundle passed to every segment builder. `vcs` and `cost_usd` are
/// precomputed in a scoped thread; `deltas` carries flash state.
#[derive(Debug)]
pub struct BuildCtx<'a> {
    pub input: &'a Input,
    pub icons: &'a crate::render::icons::Icons,
    pub palette: &'a Palette,
    pub vcs: Option<Segment>,
    pub cost_usd: Option<f64>,
    pub deltas: Deltas,
    pub settings: &'a Settings,
    pub pace_settings: &'a PaceSettings,
}

#[derive(Debug, Clone)]
pub struct Layout {
    pub lines: Vec<Vec<SegmentName>>,
}

impl fmt::Display for Layout {
    /// Render the layout back into DSL form. Lines are joined with
    /// ` | ` and segments inside a line with `,`. Round-trips through
    /// [`Layout::parse`].
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for (i, line) in self.lines.iter().enumerate() {
            if i > 0 {
                f.write_str(" | ")?;
            }
            for (j, name) in line.iter().enumerate() {
                if j > 0 {
                    f.write_str(",")?;
                }
                write!(f, "{name}")?;
            }
        }
        Ok(())
    }
}

impl Layout {
    /// Does this layout reference the given segment anywhere? Used by
    /// `render()` to skip precomputing data for segments that won't be
    /// displayed (e.g. don't walk the transcript if `Cost` isn't in the
    /// layout, don't open a git repo if `Vcs` isn't in the layout).
    #[must_use]
    pub fn contains(&self, name: SegmentName) -> bool {
        self.lines.iter().any(|line| line.contains(&name))
    }

    /// Default layout. The actionable info - context and rate limits —
    /// rides on the top line where it's hardest to miss; the cumulative
    /// figures (cost, diff) and the model name sit below. Earlier
    /// versions kept the model name on top, which buried the rate-limit
    /// countdown that users actually need to see at a glance.
    #[must_use]
    pub fn two_line() -> Self {
        use SegmentName::{Cache, Clock, Context, Cost, Diff, Dir, Model, RateLimits, Vcs};
        Self {
            lines: vec![
                vec![Dir, Context, RateLimits, Vcs],
                vec![Model, Diff, Cost, Clock, Cache],
            ],
        }
    }

    /// Parse the DSL described in this module's docstring. Returns
    /// [`ParseError`] on unknown names or empty input so misconfigured
    /// users get a clear failure rather than a silently-empty prompt.
    pub fn parse(spec: &str) -> Result<Self, ParseError> {
        let mut lines: Vec<Vec<SegmentName>> = Vec::new();
        // Accept both `|` (one-line DSL) and literal newlines (config
        // file form) as line separators - they're never valid inside a
        // segment name so the split is unambiguous.
        for raw_line in spec.split(['|', '\n']) {
            let trimmed = raw_line.trim();
            if trimmed.is_empty() {
                continue;
            }
            let mut line = Vec::new();
            for tok in trimmed.split(',') {
                let tok = tok.trim();
                if tok.is_empty() {
                    continue;
                }
                let name =
                    SegmentName::parse(tok).ok_or_else(|| ParseError::Unknown(tok.to_string()))?;
                line.push(name);
            }
            if !line.is_empty() {
                lines.push(line);
            }
        }
        if lines.is_empty() {
            return Err(ParseError::Empty);
        }
        Ok(Self { lines })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ParseError {
    #[error("unknown segment `{0}`")]
    Unknown(String),
    #[error("layout is empty")]
    Empty,
}

impl FromStr for Layout {
    type Err = ParseError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Self::parse(s)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_two_line_dsl() {
        let layout = Layout::parse("dir,vcs,model | cost,diff,context,rate_limits").unwrap();
        assert_eq!(layout.lines.len(), 2);
        assert_eq!(
            layout.lines[0],
            vec![SegmentName::Dir, SegmentName::Vcs, SegmentName::Model]
        );
        assert_eq!(
            layout.lines[1],
            vec![
                SegmentName::Cost,
                SegmentName::Diff,
                SegmentName::Context,
                SegmentName::RateLimits,
            ]
        );
    }

    #[test]
    fn parses_newline_separated_form() {
        let spec = "dir, vcs\ncost, context\n";
        let layout = Layout::parse(spec).unwrap();
        assert_eq!(layout.lines.len(), 2);
    }

    #[test]
    fn aliases_resolve_to_canonical_name() {
        let layout = Layout::parse("git, ctx, rates").unwrap();
        assert_eq!(
            layout.lines[0],
            vec![
                SegmentName::Vcs,
                SegmentName::Context,
                SegmentName::RateLimits
            ]
        );
    }

    #[test]
    fn unknown_segment_errors() {
        let err = Layout::parse("dir, foo").unwrap_err();
        match err {
            ParseError::Unknown(name) => assert_eq!(name, "foo"),
            _ => panic!("expected Unknown"),
        }
    }

    #[test]
    fn empty_layout_errors() {
        assert!(matches!(Layout::parse("   "), Err(ParseError::Empty)));
        assert!(matches!(Layout::parse("|"), Err(ParseError::Empty)));
    }

    #[test]
    fn default_two_line_has_two_lines() {
        let l = Layout::two_line();
        assert_eq!(l.lines.len(), 2);
        assert_eq!(l.lines[0][0], SegmentName::Dir);
    }
}
