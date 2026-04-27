//! jj collector: build the styled VCS info segment via `jj-lib`, without
//! ever snapshotting the working copy.

use std::path::Path;
use std::time::UNIX_EPOCH;

use jj_lib::config::StackedConfig;
use jj_lib::local_working_copy::{FileType, LocalWorkingCopy};
use jj_lib::repo::{Repo, StoreFactories};
use jj_lib::settings::UserSettings;
use jj_lib::workspace::{Workspace, default_working_copy_factories};
use pollster::FutureExt as _;

use crate::vcs::jj_prefix;

use crate::render::colors::Palette;
use crate::render::icons::Icons;
use crate::render::segment::Segment;

fn user_settings() -> Option<UserSettings> {
    UserSettings::from_config(StackedConfig::with_defaults()).ok()
}

pub(super) fn collect(dir: &Path, icons: &Icons, pal: &Palette) -> Option<Segment> {
    let settings = user_settings()?;
    let workspace = Workspace::load(
        &settings,
        dir,
        &StoreFactories::default(),
        &default_working_copy_factories(),
    )
    .ok()?;

    let repo = workspace.repo_loader().load_at_head().block_on().ok()?;

    let wc_id = repo.view().get_wc_commit_id(workspace.workspace_name())?;
    let commit = repo.store().get_commit(wc_id).ok()?;
    let change_id = commit.change_id();

    let mut s = Segment::droppable();
    s.append_icon_prefix(icons.jj);

    // Bookmark on @ takes precedence visually
    let bookmark: Option<String> = repo.view().local_bookmarks().find_map(|(name, target)| {
        if target.added_ids().any(|id| id == wc_id) {
            Some(name.as_symbol().to_string())
        } else {
            None
        }
    });

    let full_hex = change_id.reverse_hex();
    let prefix_len = jj_prefix::shortest_prefix_len(&workspace, &repo, change_id)
        .min(full_hex.len())
        .max(1);
    let head: String = full_hex.chars().take(prefix_len).collect();
    s.append_styled(head, pal.cyan);

    if let Some(b) = bookmark {
        s.append_spaced_styled(format!("({b})"), pal.magenta);
    }

    // Dirty indicator
    match working_copy_dirty(&workspace) {
        Some(true) => s.append_spaced_styled(icons.dirty, pal.yellow),
        Some(false) => s.append_spaced_styled(icons.clean, pal.green),
        None => s.append_spaced_styled(icons.untracked, pal.dim),
    };

    if commit.has_conflict() {
        s.append_spaced_styled(format!("{} conflict", icons.conflict), pal.red);
    }

    Some(s)
}

const DIRTY_CHECK_BUDGET: usize = 4096;

fn working_copy_dirty(workspace: &Workspace) -> Option<bool> {
    // Intentionally avoid jj-lib's snapshot/status path here: the statusline is
    // a read-only prompt hook and must not write a new working-copy commit just
    // to decide which glyph to render. jj-lib exposes `FileState::is_clean()`
    // for comparing two recorded states, but constructing the current disk
    // `FileState` from metadata is private, so this mirrors that cheap metadata
    // check while staying non-mutating.
    let wc = workspace
        .working_copy()
        .downcast_ref::<LocalWorkingCopy>()?;
    let states = wc.file_states().ok()?;
    let root = workspace.workspace_root();

    let mut checked = 0usize;
    for (repo_path, state) in states.iter() {
        if checked >= DIRTY_CHECK_BUDGET {
            return None;
        }
        if !matches!(state.file_type, FileType::Normal { .. }) {
            continue;
        }
        let Ok(fs_path) = repo_path.to_fs_path(root) else {
            continue;
        };
        let Ok(meta) = std::fs::symlink_metadata(&fs_path) else {
            return Some(true);
        };
        if !meta.is_file() {
            return Some(true);
        }
        if meta.len() != state.size {
            return Some(true);
        }
        if let Ok(modified) = meta.modified()
            && let Ok(dur) = modified.duration_since(UNIX_EPOCH)
            && i64::try_from(dur.as_millis()).ok() != Some(state.mtime.0)
        {
            return Some(true);
        }
        checked += 1;
    }
    Some(false)
}
