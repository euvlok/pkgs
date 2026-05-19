//! Git collector via `gix`.

use std::path::Path;

use gix::bstr::BString;
use gix::status::Item as StatusItem;
use gix::status::UntrackedFiles;
use gix::status::index_worktree;

use crate::config::schema::VcsSegmentConfig;
use crate::vcs::{Operation, Tracking, VcsInfo, VcsProvider, WorktreeStatus};

pub(super) fn collect(dir: &Path, config: &VcsSegmentConfig) -> Option<VcsInfo> {
    let repo = open_repo(dir)?;

    let head_ref = repo.head_ref().ok().flatten();
    let head_id = repo.head_id().ok();
    let branch_name: Option<String> = head_ref.as_ref().map(|r| r.name().shorten().to_string());
    let short_hash = head_id.as_ref().map(|id| id.to_hex_with_len(7).to_string());

    let operation = repo.state().map(|state| {
        use gix::state::InProgress::{
            ApplyMailbox, ApplyMailboxRebase, Bisect, CherryPick, CherryPickSequence, Merge,
            Rebase, RebaseInteractive, Revert, RevertSequence,
        };
        match state {
            Merge => Operation::Merge,
            Rebase | RebaseInteractive | ApplyMailbox | ApplyMailboxRebase => Operation::Rebase,
            CherryPick | CherryPickSequence => Operation::CherryPick,
            Revert | RevertSequence => Operation::Revert,
            Bisect => Operation::Bisect,
        }
    });

    Some(VcsInfo {
        provider: VcsProvider::Git,
        branch: branch_name,
        hash: short_hash,
        no_commits: head_id.is_none() && head_ref.is_some(),
        detached: head_ref.is_none() && head_id.is_some(),
        tracking: if config.show_ahead_behind {
            upstream_divergence(&repo)
        } else {
            Tracking::default()
        },
        operation,
        status: config.show_dirty.then(|| compute_status(&repo)).flatten(),
        stash_count: if config.show_stash {
            count_stash(&repo)
        } else {
            0
        },
        ..VcsInfo::default()
    })
}

fn open_repo(dir: &Path) -> Option<gix::Repository> {
    gix::open_opts(
        dir,
        gix::open::Options::default()
            .config_overrides(["core.filesRefLockTimeout=0", "core.packedRefsTimeout=0"]),
    )
    .ok()
}

#[expect(clippy::literal_string_with_formatting_args)]
fn upstream_divergence(repo: &gix::Repository) -> Tracking {
    let (Ok(head), Ok(upstream)) = (
        repo.rev_parse_single("HEAD"),
        repo.rev_parse_single("HEAD@{upstream}"),
    ) else {
        return Tracking::default();
    };
    let head_oid = head.detach();
    let up_oid = upstream.detach();
    let count_walk = |from, hide| {
        repo.rev_walk([from])
            .with_hidden([hide])
            .all()
            .ok()
            .map_or(0, |w| w.filter_map(Result::ok).count())
    };
    Tracking {
        ahead: count_walk(head_oid, up_oid),
        behind: count_walk(up_oid, head_oid),
    }
}

fn compute_status(repo: &gix::Repository) -> Option<WorktreeStatus> {
    let mut status = WorktreeStatus::default();

    let platform = repo
        .status(gix::progress::Discard)
        .ok()?
        .untracked_files(UntrackedFiles::Collapsed);
    let iter = platform.into_iter(Vec::<BString>::new()).ok()?;

    for item in iter.filter_map(Result::ok) {
        match item {
            StatusItem::TreeIndex(_) => status.staged = true,
            StatusItem::IndexWorktree(iw) => match iw {
                index_worktree::Item::Modification { .. }
                | index_worktree::Item::Rewrite { .. } => status.unstaged = true,
                index_worktree::Item::DirectoryContents { entry, .. } => {
                    use gix::dir::entry::Status;
                    if matches!(entry.status, Status::Untracked) {
                        status.untracked = true;
                    }
                }
            },
        }
        if status.staged && status.unstaged && status.untracked {
            break;
        }
    }

    Some(status)
}

fn count_stash(repo: &gix::Repository) -> usize {
    let Ok(reference) = repo.find_reference("refs/stash") else {
        return 0;
    };
    let mut log_iter = reference.log_iter();
    let Ok(Some(iter)) = log_iter.all() else {
        return 0;
    };
    iter.filter_map(Result::ok).count()
}
