//! claude-statusline binary entry point.

use std::process::ExitCode;

use clap::Parser;

use claude_statusline::cli::Cli;

fn main() -> ExitCode {
    let cli = Cli::parse();
    claude_statusline::app::run(&cli)
}
