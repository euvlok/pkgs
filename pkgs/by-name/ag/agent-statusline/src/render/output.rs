//! Structured JSON render output.

use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct RenderOutput {
    pub text: String,
    pub lines: Vec<RenderedLine>,
    pub warnings: Vec<RenderWarning>,
}

#[derive(Debug, Serialize)]
pub struct RenderedLine {
    pub text: String,
    pub segments: Vec<RenderedSegment>,
}

#[derive(Debug, Serialize)]
pub struct RenderedSegment {
    pub id: String,
    #[serde(rename = "type")]
    pub ty: String,
    pub plain: String,
    pub width: usize,
    pub dropped: bool,
}

#[derive(Debug, Serialize)]
pub struct RenderWarning {
    pub message: String,
}
