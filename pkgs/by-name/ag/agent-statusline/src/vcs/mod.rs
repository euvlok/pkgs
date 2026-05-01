//! VCS dispatch and formatting.

use std::path::{Path, PathBuf};

mod git;
mod jj;
mod jj_prefix;

use crate::config::schema::VcsSegmentConfig;
use crate::render::colors::Palette;
use crate::render::icons::Icons;
use crate::render::segment::Segment;

/// Neutral VCS facts collected once per render and formatted by each `vcs`
/// segment according to its own TOML config.
#[derive(Clone, Debug, Default)]
pub struct VcsInfo {
    pub provider: VcsProvider,
    pub branch: Option<String>,
    pub hash: Option<String>,
    pub bookmark: Option<String>,
    pub no_commits: bool,
    pub detached: bool,
    pub tracking: Tracking,
    pub operation: Option<Operation>,
    pub status: Option<WorktreeStatus>,
    pub stash_count: usize,
    pub conflict: bool,
}

#[derive(Copy, Clone, Debug, Default, Eq, PartialEq)]
pub enum VcsProvider {
    #[default]
    Git,
    Jj,
}

#[derive(Copy, Clone, Debug, Default, Eq, PartialEq)]
pub struct Tracking {
    pub ahead: usize,
    pub behind: usize,
}

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum Operation {
    Merge,
    Rebase,
    CherryPick,
    Revert,
    Bisect,
}

#[derive(Copy, Clone, Debug, Default, Eq, PartialEq)]
pub struct WorktreeStatus {
    pub staged: bool,
    pub unstaged: bool,
    pub untracked: bool,
    pub unknown: bool,
}

/// Try to collect VCS facts for `vcs_dir`. Returns `None` if the directory is
/// neither a jj nor a git working tree (or on any error).
pub fn collect(vcs_dir: &str, config: &VcsSegmentConfig) -> Option<VcsInfo> {
    let path = PathBuf::from(vcs_dir);
    let abs = std::fs::canonicalize(&path).unwrap_or(path);

    // jj-lib's `Workspace::load` requires the *workspace root*, not an
    // arbitrary subdirectory inside it. Walk parents until we find the
    // `.jj` marker and hand that path to the jj collector.
    if let Some(jj_root) = find_jj_root(&abs)
        && let Some(info) = jj::collect(&jj_root, config)
    {
        return Some(info);
    }
    git::collect(&abs, config)
}

pub fn format(
    info: &VcsInfo,
    config: &VcsSegmentConfig,
    icons: &Icons,
    pal: &Palette,
) -> Option<Segment> {
    let mut s = Segment::droppable();
    s.append_icon_prefix(match info.provider {
        VcsProvider::Git => icons.git,
        VcsProvider::Jj => icons.jj,
    });

    match info.provider {
        VcsProvider::Git => format_git_head(&mut s, info, config, pal),
        VcsProvider::Jj => format_jj_head(&mut s, info, config, pal),
    }

    if config.show_ahead_behind {
        append_tracking(&mut s, info.tracking, icons, pal);
    }

    if let Some(operation) = info.operation {
        s.append_spaced_styled(operation_label(operation, icons), pal.red);
    }

    if config.show_dirty {
        append_status(&mut s, info.status, icons, pal);
    }

    if config.show_stash && info.stash_count > 0 {
        s.append_spaced_styled(
            format!("{}{count}", icons.stash, count = info.stash_count),
            pal.dim,
        );
    }

    if info.conflict {
        s.append_spaced_styled(format!("{} conflict", icons.conflict), pal.red);
    }

    (!s.is_empty()).then_some(s)
}

fn format_git_head(s: &mut Segment, info: &VcsInfo, config: &VcsSegmentConfig, pal: &Palette) {
    match (
        info.branch.as_deref(),
        info.hash.as_deref(),
        config.show_hash,
    ) {
        (Some(branch), Some(hash), true) => {
            s.append_styled(branch, pal.magenta);
            s.append_plain(" ");
            s.append_styled(hash, pal.dim);
        }
        (Some(branch), _, _) => {
            s.append_styled(branch, pal.magenta);
            if info.no_commits && config.show_hash {
                s.append_plain(" ");
                s.append_styled("(no commits)", pal.dim);
            }
        }
        (None, Some(hash), true) if info.detached => {
            s.append_styled("(detached)", pal.yellow);
            s.append_plain(" ");
            s.append_styled(hash, pal.dim);
        }
        (None, Some(_), false) if info.detached => {
            s.append_styled("(detached)", pal.yellow);
        }
        _ => {}
    }
}

fn format_jj_head(s: &mut Segment, info: &VcsInfo, config: &VcsSegmentConfig, pal: &Palette) {
    if config.show_hash
        && let Some(hash) = &info.hash
    {
        s.append_styled(hash, pal.cyan);
    }
    if config.show_bookmark
        && let Some(bookmark) = &info.bookmark
    {
        s.append_spaced_styled(format!("({bookmark})"), pal.magenta);
    }
}

fn append_tracking(s: &mut Segment, tracking: Tracking, icons: &Icons, pal: &Palette) {
    let mut arrows = [
        (icons.ahead, tracking.ahead),
        (icons.behind, tracking.behind),
    ]
    .into_iter()
    .filter(|(_, count)| *count > 0)
    .peekable();
    if arrows.peek().is_none() {
        return;
    }
    s.append_space();
    for (i, (icon, count)) in arrows.enumerate() {
        if i > 0 {
            s.append_space();
        }
        s.append_styled(format!("{icon}{count}"), pal.cyan);
    }
}

fn append_status(s: &mut Segment, status: Option<WorktreeStatus>, icons: &Icons, pal: &Palette) {
    match status {
        Some(status) if status.unknown => {
            s.append_spaced_styled(icons.untracked, pal.dim);
        }
        Some(status) => {
            if status.staged {
                s.append_spaced_styled(icons.staged, pal.green);
            }
            if status.unstaged {
                s.append_spaced_styled(icons.dirty, pal.yellow);
            } else if !status.staged && !status.untracked {
                s.append_spaced_styled(icons.clean, pal.green);
            }
            if status.untracked {
                s.append_spaced_styled(icons.untracked, pal.dim);
            }
        }
        None => {
            s.append_spaced_styled(icons.untracked, pal.dim);
        }
    }
}

fn operation_label(operation: Operation, icons: &Icons) -> String {
    match operation {
        Operation::Merge => format!("{} merge", icons.merge),
        Operation::Rebase => format!("{} rebase", icons.rebase),
        Operation::CherryPick => format!("{} cherry-pick", icons.cherry_pick),
        Operation::Revert => format!("{} revert", icons.revert),
        Operation::Bisect => format!("{} bisect", icons.bisect),
    }
}

/// Walk parent directories looking for a `.jj` directory and return the
/// directory that contains it (the workspace root).
fn find_jj_root(start: &Path) -> Option<PathBuf> {
    start
        .ancestors()
        .find(|p| p.join(".jj").is_dir())
        .map(Path::to_path_buf)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::schema::VcsSegmentConfig;
    use crate::render::colors::Palette;
    use crate::render::icons::IconSet;

    fn icons() -> &'static Icons {
        IconSet::Text.icons()
    }

    #[test]
    fn git_format_honors_hash_and_tracking_flags() {
        let info = VcsInfo {
            provider: VcsProvider::Git,
            branch: Some("main".to_string()),
            hash: Some("abc1234".to_string()),
            tracking: Tracking {
                ahead: 2,
                behind: 1,
            },
            ..VcsInfo::default()
        };
        let config = VcsSegmentConfig {
            show_hash: false,
            show_ahead_behind: false,
            ..VcsSegmentConfig::default()
        };

        let segment = format(&info, &config, icons(), &Palette::dark());
        assert!(segment.is_some());
        let plain = segment.map_or_else(String::new, |segment| segment.plain_text());
        assert!(plain.contains("main"));
        assert!(!plain.contains("abc1234"));
        assert!(!plain.contains('2'));
        assert!(!plain.contains('1'));
    }

    #[test]
    fn jj_format_honors_bookmark_and_dirty_flags() {
        let info = VcsInfo {
            provider: VcsProvider::Jj,
            hash: Some("kq".to_string()),
            bookmark: Some("feature".to_string()),
            status: Some(WorktreeStatus {
                unstaged: true,
                ..WorktreeStatus::default()
            }),
            ..VcsInfo::default()
        };
        let config = VcsSegmentConfig {
            show_bookmark: false,
            show_dirty: false,
            ..VcsSegmentConfig::default()
        };

        let segment = format(&info, &config, icons(), &Palette::dark());
        assert!(segment.is_some());
        let plain = segment.map_or_else(String::new, |segment| segment.plain_text());
        assert!(plain.contains("kq"));
        assert!(!plain.contains("feature"));
        assert!(!plain.contains("dirty"));
    }

    #[test]
    fn unknown_status_renders_unknown_marker() {
        let info = VcsInfo {
            provider: VcsProvider::Jj,
            hash: Some("k".to_string()),
            status: Some(WorktreeStatus {
                unknown: true,
                ..WorktreeStatus::default()
            }),
            ..VcsInfo::default()
        };

        let segment = format(
            &info,
            &VcsSegmentConfig::default(),
            icons(),
            &Palette::dark(),
        );
        assert!(segment.is_some());
        let plain = segment.map_or_else(String::new, |segment| segment.plain_text());
        assert!(plain.contains('?'));
    }
}
