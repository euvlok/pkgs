//! agent-statusline binary entry point.

use std::process::ExitCode;

use clap::Parser;

use agent_statusline::cli::Cli;

fn main() -> ExitCode {
    let cli = Cli::parse();
    agent_statusline::app::run(&cli)
}
