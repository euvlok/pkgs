//! Structured statusline AST.
//!
//! Each [`Segment`] is a list of styled [`Cell`]s. The renderer assembles
//! cells into final ANSI output and computes display widths from raw text
//! (no regex strip needed, because the text and the style live in
//! separate fields).
//!
//! Builders in [`crate::render::builders`] produce `Option<Segment>`s;
//! the renderer in [`crate::render`] consumes them. This is the only
//! place that knows about styled text - every other module manipulates
//! plain `&str` / `String` plus [`anstyle::Style`] values.

use anstyle::{Reset, Style};
use compact_str::CompactString;
use unicode_width::UnicodeWidthStr;

/// A run of text with a single style applied. Cells are the leaves of
/// the AST: they don't combine, they don't compose styles, they're just
/// "render this text in this color".
///
/// `text` is a [`CompactString`]: strings up to 24 bytes (which covers
/// nearly all statusline content — icons, short labels, `$0.42`, branch
/// names) are stored inline without a heap allocation.
///
/// An optional `link` wraps the cell in an OSC 8 hyperlink when the
/// terminal supports it.
#[derive(Debug, Clone)]
pub struct Cell {
    pub text: CompactString,
    pub style: Style,
    pub link: Option<CompactString>,
}

impl Cell {
    #[must_use]
    pub fn new(text: impl Into<CompactString>, style: Style) -> Self {
        Self {
            text: text.into(),
            style,
            link: None,
        }
    }

    #[must_use]
    pub fn plain(text: impl Into<CompactString>) -> Self {
        Self::new(text, Style::new())
    }

    #[must_use]
    pub fn linked(
        text: impl Into<CompactString>,
        style: Style,
        url: impl Into<CompactString>,
    ) -> Self {
        Self {
            text: text.into(),
            style,
            link: Some(url.into()),
        }
    }

    #[must_use]
    pub fn width(&self) -> usize {
        UnicodeWidthStr::width(self.text.as_str())
    }

    pub fn write_to(&self, out: &mut String) {
        use std::fmt::Write as _;
        let link = self
            .link
            .as_deref()
            .map(anstyle_hyperlink::Hyperlink::with_url)
            .unwrap_or_default();
        if self.style.is_plain() {
            let _ = write!(out, "{link}{}{link:#}", self.text);
        } else {
            let _ = write!(out, "{link}{}{}{Reset}{link:#}", self.style, self.text);
        }
    }
}

/// Whether the renderer may elide this segment to fit within the
/// terminal width.
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum SegmentKind {
    /// First segment of a line — never dropped.
    Anchor,
    /// May be elided from the right when space is tight.
    Droppable,
}

/// A statusline chunk (one logical thing: dir, vcs info, cost, …).
///
/// `compact` is an optional shorter rendering. The fit pass prefers
/// swapping a segment to its compact form before dropping it entirely,
/// borrowing the i3bar `short_text` pattern: narrow terminals lose
/// detail, not whole segments.
#[derive(Debug, Clone)]
pub struct Segment {
    pub id: String,
    pub ty: String,
    pub cells: Vec<Cell>,
    pub kind: SegmentKind,
    pub compact: Option<Vec<Cell>>,
}

impl Segment {
    #[must_use]
    pub const fn anchor() -> Self {
        Self {
            id: String::new(),
            ty: String::new(),
            cells: Vec::new(),
            kind: SegmentKind::Anchor,
            compact: None,
        }
    }

    #[must_use]
    pub const fn droppable() -> Self {
        Self {
            id: String::new(),
            ty: String::new(),
            cells: Vec::new(),
            kind: SegmentKind::Droppable,
            compact: None,
        }
    }

    /// Replace cells with the compact form. No-op if no compact form
    /// was recorded. Returns whether a swap happened.
    pub fn apply_compact(&mut self) -> bool {
        match self.compact.take() {
            Some(cells) => {
                self.cells = cells;
                true
            }
            None => false,
        }
    }

    #[must_use]
    pub const fn has_compact(&self) -> bool {
        self.compact.is_some()
    }

    pub fn append_plain(&mut self, text: impl Into<CompactString>) -> &mut Self {
        self.cells.push(Cell::plain(text));
        self
    }

    pub fn append_space(&mut self) -> &mut Self {
        self.append_plain(" ")
    }

    pub fn append_icon_prefix(&mut self, icon: &str) -> &mut Self {
        if !icon.is_empty() {
            self.append_plain(format!("{icon} "));
        }
        self
    }

    pub fn append_styled(&mut self, text: impl Into<CompactString>, style: Style) -> &mut Self {
        self.cells.push(Cell::new(text, style));
        self
    }

    pub fn append_spaced_styled(
        &mut self,
        text: impl Into<CompactString>,
        style: Style,
    ) -> &mut Self {
        self.append_space().append_styled(text, style)
    }

    pub fn append_linked(
        &mut self,
        text: impl Into<CompactString>,
        style: Style,
        url: impl Into<CompactString>,
    ) -> &mut Self {
        self.cells.push(Cell::linked(text, style, url));
        self
    }

    pub fn plain(mut self, text: impl Into<CompactString>) -> Self {
        self.append_plain(text);
        self
    }

    pub fn styled(mut self, text: impl Into<CompactString>, style: Style) -> Self {
        self.append_styled(text, style);
        self
    }

    pub fn linked(
        mut self,
        text: impl Into<CompactString>,
        style: Style,
        url: impl Into<CompactString>,
    ) -> Self {
        self.append_linked(text, style, url);
        self
    }

    pub fn compact(mut self) -> Self {
        self.compact = Some(self.cells.clone());
        self
    }

    pub fn with_compact(mut self, cells: Vec<Cell>) -> Self {
        self.compact = Some(cells);
        self
    }

    pub const fn some(self) -> Option<Self> {
        Some(self)
    }

    #[must_use]
    pub fn width(&self) -> usize {
        self.cells.iter().map(Cell::width).sum()
    }

    #[must_use]
    pub fn plain_text(&self) -> String {
        self.cells.iter().map(|cell| cell.text.as_str()).collect()
    }

    pub const fn is_empty(&self) -> bool {
        self.cells.is_empty()
    }

    pub fn write_to(&self, out: &mut String) {
        for cell in &self.cells {
            cell.write_to(out);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cell_width_counts_emoji_and_ascii() {
        assert_eq!(Cell::plain("hello").width(), 5);
        assert!(Cell::plain("🌿").width() >= 1);
    }

    #[test]
    fn plain_cell_emits_no_escapes() {
        let mut out = String::new();
        Cell::plain("foo").write_to(&mut out);
        assert_eq!(out, "foo");
    }

    #[test]
    fn styled_cell_wraps_in_sgr_and_reset() {
        let mut out = String::new();
        Cell::new("foo", anstyle::AnsiColor::Green.on_default()).write_to(&mut out);
        assert!(out.starts_with("\x1b["));
        assert!(out.contains("foo"));
        assert!(out.ends_with("\x1b[0m"));
    }

    #[test]
    fn segment_width_sums_cells() {
        let mut s = Segment::droppable();
        s.append_plain("ab");
        s.append_plain("cde");
        assert_eq!(s.width(), 5);
    }
}
