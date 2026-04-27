//! Glyph sets for the pace segment.
//!
//! Four states each need a glyph: `on-pace`, `too-hot`, `cool`, and
//! `cold-start`. We expose several font-specific sets so users on
//! non-Nerd-Font terminals still get something readable.

use clap::ValueEnum;

/// Which glyph family to draw.
#[derive(Copy, Clone, Debug, ValueEnum, Default, Eq, PartialEq)]
#[value(rename_all = "lower")]
pub enum PaceGlyphs {
    /// Material Design Icons (Nerd Font PUA).
    Mdi,
    /// Font Awesome (Nerd Font PUA).
    Fa,
    /// Octicons (Nerd Font PUA).
    Oct,
    /// Broadly supported color emoji (default).
    #[default]
    Emoji,
    /// ASCII / BMP-only fallback.
    Text,
}

/// Resolved glyph table.
#[derive(Copy, Clone, Debug)]
pub struct GlyphSet {
    pub on_pace: &'static str,
    pub too_hot: &'static str,
    pub cool: &'static str,
    pub cold_start: &'static str,
}

// Material Design Icons (Nerd Font PUA).
pub const MDI: GlyphSet = GlyphSet {
    // nf-md-check
    on_pace: "\u{F012C}",
    // nf-md-fire
    too_hot: "\u{F0238}",
    // nf-md-snowflake
    cool: "\u{F0717}",
    // nf-md-timer_sand
    cold_start: "\u{F051F}",
};

// Font Awesome (Nerd Font PUA).
pub const FA: GlyphSet = GlyphSet {
    // nf-fa-check
    on_pace: "\u{F00C}",
    // nf-fa-fire
    too_hot: "\u{F06D}",
    // nf-fa-snowflake
    cool: "\u{F2DC}",
    // nf-fa-hourglass_half
    cold_start: "\u{F252}",
};

// Octicons (Nerd Font PUA). Octicons is light on weather-style glyphs,
// so we reuse its general-purpose markers.
pub const OCT: GlyphSet = GlyphSet {
    // nf-oct-check
    on_pace: "\u{F42E}",
    // nf-oct-flame
    too_hot: "\u{F490}",
    // nf-oct-stop
    cool: "\u{F08F}",
    // nf-oct-hourglass
    cold_start: "\u{F498}",
};

pub const EMOJI: GlyphSet = GlyphSet {
    on_pace: "✓",
    too_hot: "🔥",
    cool: "❄",
    cold_start: "⏳",
};

pub const TEXT: GlyphSet = GlyphSet {
    on_pace: "✓",
    too_hot: "!",
    cool: "~",
    cold_start: "…",
};

impl PaceGlyphs {
    #[must_use]
    pub const fn resolve(self) -> &'static GlyphSet {
        match self {
            Self::Mdi => &MDI,
            Self::Fa => &FA,
            Self::Oct => &OCT,
            Self::Emoji => &EMOJI,
            Self::Text => &TEXT,
        }
    }
}
