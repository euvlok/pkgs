//! Multi-line statusline rendering driven by a [`Layout`].
//!
//! The renderer is now a thin string serializer: it asks each named
//! segment to build itself, then joins the resulting [`Segment`]s with a
//! visible separator and drops droppable segments from the right when
//! the line wouldn't fit in the terminal width. Every line is budgeted
//! independently - line 1 (identity) and line 2 (telemetry) wrap on
//! their own.

pub mod builders;
pub mod colors;
pub mod fit;
pub mod format;
pub mod icons;
pub mod layout;
pub mod output;
pub mod preview;
pub mod registry;
pub mod segment;
mod write;

use crate::config::ResolvedConfig;
use crate::input::Input;
use crate::render::colors::Palette;
use crate::render::icons::Icons;
use crate::render::layout::{BuildCtx, Layout, build_segment};
use crate::render::output::{RenderOutput, RenderWarning, RenderedLine, RenderedSegment};
use crate::render::segment::{Segment, SegmentKind};
use crate::vcs;

/// Convenience: render with the historical defaults. Used by tests
/// (which don't care about settings) and benches.
pub fn render(input: &Input, icons: &Icons, layout: &Layout) -> String {
    let resolved = ResolvedConfig {
        source: crate::config::Config::default(),
        display: crate::config::ResolvedDisplay {
            config: crate::config::Config::default().display,
        },
        lines: layout.lines.clone(),
        warnings: Vec::new(),
    };
    render_resolved(input, icons, &resolved, &Palette::dark())
}

pub fn render_resolved(
    input: &Input,
    icons: &Icons,
    resolved: &ResolvedConfig,
    pal: &Palette,
) -> String {
    render_output(input, icons, resolved, pal).ansi_text
}

#[derive(Debug)]
pub struct RenderedStatusline {
    pub ansi_text: String,
    pub output: RenderOutput,
    pub diagnostics: Vec<SegmentDiagnostic>,
}

#[derive(Debug, serde::Serialize)]
pub struct SegmentDiagnostic {
    pub id: String,
    #[serde(rename = "type")]
    pub ty: String,
    pub rendered: bool,
    pub plain: String,
    pub width: usize,
}

pub fn render_output(
    input: &Input,
    icons: &Icons,
    resolved: &ResolvedConfig,
    pal: &Palette,
) -> RenderedStatusline {
    let layout = Layout::new(resolved.lines.clone());
    let vcs_seg = layout
        .needs_vcs()
        .then(|| vcs::collect(&input.vcs_dir(), icons, pal))
        .flatten();

    let ctx = BuildCtx {
        input,
        icons,
        palette: pal,
        vcs: vcs_seg,
        display: &resolved.display,
        now_unix: crate::pace::now_unix(),
    };
    render_lines(&ctx, &layout, None, resolved)
}

/// Build -> fit -> write pipeline given an already-prepared [`BuildCtx`].
pub(crate) fn render_lines(
    ctx: &BuildCtx<'_>,
    layout: &Layout,
    max_cols_override: Option<usize>,
    resolved: &ResolvedConfig,
) -> RenderedStatusline {
    let icons = ctx.icons;
    let pal = ctx.palette;
    let max_cols = max_cols_override.or_else(|| {
        terminal_size::terminal_size()
            .map(|(w, _)| w.0 as usize)
            .filter(|c| *c > 10)
    });
    let separator = write::build_separator(icons.sep.as_ref(), pal);
    let mut diagnostics = Vec::new();

    let mut lines: Vec<Vec<Segment>> = layout
        .lines
        .iter()
        .map(|line| {
            let mut segments: Vec<Segment> = line
                .iter()
                .filter_map(|spec| {
                    let segment = build_segment(ctx, spec).filter(|s| !s.is_empty());
                    diagnostics.push(SegmentDiagnostic {
                        id: spec.id.clone(),
                        ty: spec.config.ty().to_string(),
                        rendered: segment.is_some(),
                        plain: segment
                            .as_ref()
                            .map_or_else(String::new, Segment::plain_text),
                        width: segment.as_ref().map_or(0, Segment::width),
                    });
                    segment
                })
                .collect();
            // The layout, not the individual builder, defines the line anchor.
            // Missing data can make the named first segment disappear, so anchor
            // the first segment that actually renders and make all later ones
            // droppable. This keeps custom layouts such as `model,diff` from
            // going blank on narrow terminals, while allowing `dir` to be
            // dropped when the user places it later in a line.
            for (i, segment) in segments.iter_mut().enumerate() {
                segment.kind = if i == 0 {
                    SegmentKind::Anchor
                } else {
                    SegmentKind::Droppable
                };
            }
            segments
        })
        .collect();

    let col_widths: Vec<usize> = if resolved.display.config.align {
        fit_with_alignment(&mut lines, separator.width, max_cols)
    } else {
        fit_unaligned(&mut lines, separator.width, max_cols);
        Vec::new()
    };

    let mut ansi_text = String::new();
    let mut rendered_lines = Vec::new();
    for (i, segments) in lines.iter().enumerate() {
        if i > 0 {
            ansi_text.push('\n');
        }
        write::write_line(&mut ansi_text, segments, &separator, &col_widths);
        let text = write::plain_line(segments, &separator, &col_widths);
        let rendered_segments = segments
            .iter()
            .map(|segment| RenderedSegment {
                id: segment.id.clone(),
                ty: segment.ty.clone(),
                plain: segment.plain_text(),
                width: segment.width(),
                dropped: false,
            })
            .collect();
        rendered_lines.push(RenderedLine {
            text,
            segments: rendered_segments,
        });
    }
    let text = rendered_lines
        .iter()
        .map(|line| line.text.as_str())
        .collect::<Vec<_>>()
        .join("\n");
    let warnings = resolved
        .warnings
        .iter()
        .map(|warning| RenderWarning {
            message: warning.message.clone(),
        })
        .collect();
    RenderedStatusline {
        ansi_text,
        output: RenderOutput {
            text,
            lines: rendered_lines,
            warnings,
        },
        diagnostics,
    }
}

pub use fit::{aligned_width, column_widths, fit_unaligned, fit_with_alignment};

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used, clippy::expect_used)]

    use super::*;
    use crate::config::resolve;
    use crate::config::schema::{Config, SegmentConfig, SpeedSegmentConfig};
    use crate::input::{Cost, Input};
    use crate::render::icons::IconSet;

    fn icons() -> &'static Icons {
        IconSet::Text.icons()
    }

    #[test]
    fn columns_align_across_lines() {
        use crate::render::segment::Segment;
        let p = Palette::dark();
        let a1 = Segment::anchor().plain("claude-statusline");
        let a2 = Segment::anchor().plain("Opus");
        let b1 = Segment::anchor().plain("here");
        let b2 = Segment::anchor().plain("5h 7%");
        let lines = vec![vec![a1, a2], vec![b1, b2]];
        let sep = write::build_separator("│", &p);
        let widths = column_widths(&lines);
        let mut out = String::new();
        for (i, line) in lines.iter().enumerate() {
            if i > 0 {
                out.push('\n');
            }
            write::write_line(&mut out, line, &sep, &widths);
        }
        let plain = anstream::adapter::strip_str(&out).to_string();
        let mut sep_cols: Vec<usize> = Vec::new();
        for line in plain.lines() {
            sep_cols.push(line.find('│').expect("separator missing"));
        }
        assert_eq!(sep_cols[0], sep_cols[1], "separators misaligned: {plain:?}");
    }

    #[test]
    fn last_segment_is_not_padded() {
        use crate::render::segment::Segment;
        let p = Palette::dark();
        let a1 = Segment::anchor().plain("aaaa");
        let a2 = Segment::anchor().plain("b");
        let c1 = Segment::anchor().plain("a");
        let c2 = Segment::anchor().plain("bbbbbb");
        let lines = vec![vec![a1, a2], vec![c1, c2]];
        let sep = write::build_separator("│", &p);
        let widths = column_widths(&lines);
        let mut out = String::new();
        for (i, line) in lines.iter().enumerate() {
            if i > 0 {
                out.push('\n');
            }
            write::write_line(&mut out, line, &sep, &widths);
        }
        let plain = anstream::adapter::strip_str(&out).to_string();
        for line in plain.lines() {
            assert_eq!(line, line.trim_end(), "trailing whitespace in {line:?}");
        }
    }

    #[test]
    fn default_toml_config_renders_non_empty_text() {
        let resolved = resolve::resolve(Config::default());
        let input = Input {
            workspace: crate::input::Workspace {
                current_dir: Some("/tmp/foo".into()),
            },
            ..Default::default()
        };
        let out = render_output(&input, icons(), &resolved, &Palette::dark());
        assert!(!out.output.text.trim().is_empty());
    }

    #[test]
    fn structured_output_includes_segment_ids() {
        let resolved = resolve::resolve(Config::default());
        let input = Input {
            cost: Cost {
                total_lines_added: Some(342),
                total_lines_removed: Some(89),
                ..Default::default()
            },
            ..Default::default()
        };
        let out = render_output(&input, icons(), &resolved, &Palette::dark());
        assert!(
            out.output
                .lines
                .iter()
                .flat_map(|line| &line.segments)
                .any(|segment| segment.id == "changes" && segment.plain.contains("+342"))
        );
    }

    #[test]
    fn multiple_dir_instances_render() {
        let mut config = Config::default();
        config.statusline.lines = vec![vec!["dir".to_string(), "dir_full".to_string()]];
        let dir = config.segments.get("dir").cloned().unwrap();
        config.segments.insert("dir_full".to_string(), dir);
        let resolved = resolve::resolve(config);
        let input = Input {
            workspace: crate::input::Workspace {
                current_dir: Some("/tmp/foo".into()),
            },
            ..Default::default()
        };
        let out = render_output(&input, icons(), &resolved, &Palette::dark());
        let ids = out.output.lines[0]
            .segments
            .iter()
            .map(|segment| segment.id.as_str())
            .collect::<Vec<_>>();
        assert_eq!(ids, vec!["dir", "dir_full"]);
    }

    #[test]
    fn unknown_segment_id_warns_and_is_skipped() {
        let mut config = Config::default();
        config.statusline.lines = vec![vec!["dir".to_string(), "missing".to_string()]];
        let resolved = resolve::resolve(config);
        assert_eq!(resolved.lines[0].len(), 1);
        assert!(resolved.warnings[0].message.contains("missing"));
    }

    #[test]
    fn all_invalid_layout_falls_back_to_default() {
        let mut config = Config::default();
        config.statusline.lines = vec![vec!["missing".to_string()]];
        let resolved = resolve::resolve(config);
        assert!(
            resolved
                .lines
                .iter()
                .flatten()
                .any(|segment| segment.id == "dir")
        );
    }

    #[test]
    fn all_builtin_segment_types_have_capabilities() {
        let config = Config::default();
        for segment in config.segments.values() {
            assert!(
                registry::SEGMENTS
                    .iter()
                    .any(|spec| spec.ty == segment.ty()),
                "missing capability for {:?}",
                segment.ty()
            );
        }
        assert!(
            registry::SEGMENTS
                .iter()
                .any(|spec| spec.ty == SegmentConfig::Speed(SpeedSegmentConfig::default()).ty())
        );
    }
}
