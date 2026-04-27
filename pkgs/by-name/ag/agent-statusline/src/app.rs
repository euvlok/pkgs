//! Application-level orchestration.

use std::borrow::Cow;
use std::io::{self, Read as _, Write as _};
use std::process::ExitCode;

use anstream::AutoStream;
use schemars::schema_for;
use serde::Serialize;

use crate::cli::Cli;
use crate::config::schema::{ColorMode, DisplayConfig, IconSetConfig};
use crate::config::{self, Config, LoadedConfig, OutputFormat, ResolvedConfig};
use crate::input::{Input, InputSource};
use crate::render::colors::Palette;
use crate::render::icons::{IconSet, Icons};
use crate::render::layout::theme_mode;
use crate::render::output::{RenderOutput, RenderWarning};
use crate::render::preview::preview_with;
use crate::render::registry::CAPABILITIES;
use crate::render::{RenderedStatusline, SegmentDiagnostic, render_output};
use crate::theme;

const MAX_PAYLOAD: u64 = 1 << 20;

pub fn resolve_loaded(loaded: &LoadedConfig) -> ResolvedConfig {
    let mut resolved = config::resolve::resolve(loaded.config.clone());
    resolved.warnings.extend(loaded.warnings.clone());
    resolved
}

pub fn resolved_icons(display: &DisplayConfig) -> Cow<'static, Icons> {
    let base = match display.icons {
        IconSetConfig::Nerd => IconSet::Nerd.icons(),
        IconSetConfig::Emoji => IconSet::Emoji.icons(),
        IconSetConfig::Text => IconSet::Text.icons(),
    };
    let mut icons = base.clone();
    icons.sep = Cow::Owned(display.separator.clone());
    Cow::Owned(icons)
}

pub const fn color_choice(color: ColorMode) -> anstream::ColorChoice {
    match color {
        ColorMode::Auto => anstream::ColorChoice::Auto,
        ColorMode::Always => anstream::ColorChoice::Always,
        ColorMode::Never => anstream::ColorChoice::Never,
    }
}

pub fn palette_for(display: &DisplayConfig) -> Palette {
    if matches!(display.color, ColorMode::Never) {
        Palette::dark()
    } else {
        Palette::for_theme(theme::detect(theme_mode(display.theme)))
    }
}

pub fn parse_input(json: Option<&str>, reader: impl io::Read) -> Input {
    if let Some(json) = json {
        return serde_json::from_str(json).unwrap_or_default();
    }

    let mut buf = Vec::with_capacity(4096);
    if reader.take(MAX_PAYLOAD).read_to_end(&mut buf).is_ok() {
        serde_json::from_slice(&buf).unwrap_or_default()
    } else {
        Input::default()
    }
}

pub fn render_statusline(
    input: &Input,
    icons: &Icons,
    resolved: &ResolvedConfig,
    palette: &Palette,
) -> RenderedStatusline {
    render_output(input, icons, resolved, palette)
}

pub fn fallback_dir() -> String {
    Input::default().dir_name()
}

pub fn run(cli: &Cli) -> ExitCode {
    if cli.schema {
        return print_json(&schema_for!(Config));
    }

    if cli.defaults {
        let format = cli.format(OutputFormat::Text);
        return print_defaults(format);
    }

    if cli.capabilities {
        return print_json(&CAPABILITIES);
    }

    let loaded = if cli.inspect {
        match config::load(cli.config.as_deref()) {
            Ok(loaded) => loaded,
            Err(err) => {
                let _ = writeln!(io::stderr().lock(), "{err}");
                return ExitCode::FAILURE;
            }
        }
    } else {
        config::load_or_default(cli.config.as_deref())
    };

    let resolved = resolve_loaded(&loaded);
    let icons = resolved_icons(&resolved.display.config);
    let palette = palette_for(&resolved.display.config);
    let format = cli.format(resolved.display.config.format);

    if cli.preview {
        let rendered = preview_with(icons.as_ref(), &resolved, &palette, None);
        return print_rendered(&rendered, format, resolved.display.config.color);
    }

    std::panic::set_hook(Box::new(|_| {}));

    let input = parse_input(cli.input_json.as_deref(), io::stdin().lock());

    if cli.inspect {
        let rendered = render_statusline(&input, icons.as_ref(), &resolved, &palette);
        return print_json(&InspectOutput::new(&loaded, &resolved, &input, &rendered));
    }

    let result =
        std::panic::catch_unwind(|| render_statusline(&input, icons.as_ref(), &resolved, &palette));

    match result {
        Ok(rendered) => print_rendered(&rendered, format, resolved.display.config.color),
        Err(_) => print_fallback(format),
    }
}

fn print_rendered(
    rendered: &RenderedStatusline,
    format: OutputFormat,
    color: ColorMode,
) -> ExitCode {
    match format {
        OutputFormat::Text => {
            let mut stdout = AutoStream::new(io::stdout().lock(), color_choice(color));
            let _ = stdout.write_all(rendered.ansi_text.as_bytes());
            ExitCode::SUCCESS
        }
        OutputFormat::Json => print_json(&rendered.output),
    }
}

fn print_fallback(format: OutputFormat) -> ExitCode {
    let text = fallback_dir();
    match format {
        OutputFormat::Text => {
            let _ = io::stdout().lock().write_all(text.as_bytes());
            ExitCode::SUCCESS
        }
        OutputFormat::Json => {
            let output = RenderOutput {
                text,
                lines: Vec::new(),
                warnings: vec![RenderWarning {
                    message: "render panicked; emitted fallback directory".to_string(),
                }],
            };
            print_json(&output)
        }
    }
}

fn print_defaults(format: OutputFormat) -> ExitCode {
    let config = Config::default();
    match format {
        OutputFormat::Json => print_json(&config),
        OutputFormat::Text => match toml::to_string_pretty(&config) {
            Ok(toml) => {
                let _ = io::stdout().lock().write_all(toml.as_bytes());
                ExitCode::SUCCESS
            }
            Err(err) => {
                let _ = writeln!(io::stderr().lock(), "{err}");
                ExitCode::FAILURE
            }
        },
    }
}

fn print_json(value: &impl Serialize) -> ExitCode {
    match serde_json::to_string_pretty(value) {
        Ok(json) => {
            let mut out = io::stdout().lock();
            let _ = out.write_all(json.as_bytes());
            let _ = out.write_all(b"\n");
            ExitCode::SUCCESS
        }
        Err(err) => {
            let _ = writeln!(io::stderr().lock(), "{err}");
            ExitCode::FAILURE
        }
    }
}

#[derive(Debug, Serialize)]
struct InspectOutput<'a> {
    config_path: Option<String>,
    source: &'static str,
    resolved: InspectResolved,
    segments: &'a [SegmentDiagnostic],
    warnings: Vec<InspectWarning>,
}

#[derive(Debug, Serialize)]
struct InspectResolved {
    lines: Vec<Vec<String>>,
}

#[derive(Debug, Serialize)]
struct InspectWarning {
    message: String,
}

impl<'a> InspectOutput<'a> {
    fn new(
        loaded: &LoadedConfig,
        resolved: &ResolvedConfig,
        input: &Input,
        rendered: &'a RenderedStatusline,
    ) -> Self {
        let warnings = resolved
            .warnings
            .iter()
            .map(|warning| InspectWarning {
                message: warning.message.clone(),
            })
            .collect();
        Self {
            config_path: loaded
                .path
                .as_ref()
                .map(|path| path.to_string_lossy().into_owned()),
            source: source_name(input.source),
            resolved: InspectResolved {
                lines: resolved
                    .lines
                    .iter()
                    .map(|line| line.iter().map(|segment| segment.id.clone()).collect())
                    .collect(),
            },
            segments: &rendered.diagnostics,
            warnings,
        }
    }
}

const fn source_name(source: InputSource) -> &'static str {
    match source {
        InputSource::Claude => "claude",
        InputSource::Codex => "codex",
    }
}
