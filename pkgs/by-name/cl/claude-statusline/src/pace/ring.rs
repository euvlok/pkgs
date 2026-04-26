//! Persistent `(timestamp, used_pct)` sample ring.
//!
//! The pace segment's entire persistent state: a small postcard-encoded
//! file in the platform cache directory, capped at a single 5h window's
//! worth of samples. Rewritten via plain `fs::write` only when the new
//! sample materially differs from the last persisted one (see
//! [`should_persist_append`]). Tight render loops collapse to zero I/O.
//! Torn writes / format-version mismatch / decode failure all collapse
//! to "start fresh".

use std::fs;
use std::path::PathBuf;
use std::sync::OnceLock;

use serde::{Deserialize, Serialize};

/// Bumped when the on-disk layout changes incompatibly. Mismatch ⇒ start fresh.
const VERSION: u32 = 2;

/// Upper bound on in-memory + on-disk sample count.
///
/// One 5h window at a realistic render cadence fits in well under this,
/// but we cap to keep the file bounded when the user is running renders
/// in a tight loop.
pub const MAX_SAMPLES: usize = 256;

/// Skip the ring rewrite if the last persisted sample is within ε of the
/// new one in pct AND closer than this many seconds in time. Tight render
/// loops (`--watch`, status hooks firing on every keystroke) collapse to
/// no I/O; the next render with movement or after the gap re-persists.
const PERSIST_DEDUP_SECS: u64 = 15;
const PCT_EPS: f64 = 1e-9;

/// Heuristic: should we bother rewriting the ring after appending `new`
/// onto a list whose last element is `last`? `None` last means "ring was
/// empty or just got trimmed" — always persist in that case.
#[must_use]
pub fn should_persist_append(last: Option<&PctSample>, new: &PctSample) -> bool {
    let Some(last) = last else { return true };
    if (last.used_pct - new.used_pct).abs() > PCT_EPS {
        return true;
    }
    new.ts_unix.saturating_sub(last.ts_unix) > PERSIST_DEDUP_SECS
}

/// A single observation.
#[derive(Copy, Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct PctSample {
    pub ts_unix: u64,
    pub used_pct: f64,
}

#[derive(Serialize, Deserialize)]
struct RingFile {
    version: u32,
    samples: Vec<PctSample>,
}

/// Resolve the cache file path. `None` when the platform cache dir is
/// unavailable (e.g. $HOME missing in some CI sandboxes). Memoized — the
/// path is stable for the life of the process.
fn ring_path() -> Option<PathBuf> {
    static CACHED: OnceLock<Option<PathBuf>> = OnceLock::new();
    CACHED
        .get_or_init(|| {
            Some(
                dirs::cache_dir()?
                    .join("claude-statusline")
                    .join("pace")
                    .join("samples.bin"),
            )
        })
        .clone()
}

/// Load the ring, returning an empty vector on any failure (missing
/// file, version mismatch, decode error). The caller treats that as
/// "start fresh".
#[must_use]
pub fn load_ring() -> Vec<PctSample> {
    let Some(path) = ring_path() else {
        return Vec::new();
    };
    let Ok(bytes) = fs::read(path) else {
        return Vec::new();
    };
    let Ok(file): Result<RingFile, _> = postcard::from_bytes(&bytes) else {
        return Vec::new();
    };
    if file.version != VERSION {
        return Vec::new();
    }
    file.samples
}

/// Replace the cache file with the given samples. Silent on I/O failure
/// — the pace segment degrades gracefully (a corrupt or missing file
/// just resets to warmup next render). Plain `fs::write` instead of an
/// atomic-rename dance: a torn write costs us at most one warmup cycle,
/// and the syscall savings show up in every render.
pub fn persist_ring(samples: &[PctSample]) {
    let Some(path) = ring_path() else { return };
    let Some(parent) = path.parent() else { return };
    let count = samples.len().min(MAX_SAMPLES);
    let start = samples.len().saturating_sub(count);
    let file = RingFile {
        version: VERSION,
        samples: samples[start..].to_vec(),
    };
    let Ok(bytes) = postcard::to_allocvec(&file) else {
        return;
    };
    if fs::write(&path, &bytes).is_ok() {
        return;
    }
    // First write of the session: parent dir may not exist yet. Create
    // it and try once more. Avoids the create_dir_all syscall on every
    // subsequent render.
    if fs::create_dir_all(parent).is_ok() {
        let _ = fs::write(&path, &bytes);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn encode(samples: &[PctSample]) -> Vec<u8> {
        let count = samples.len().min(MAX_SAMPLES);
        let start = samples.len().saturating_sub(count);
        postcard::to_allocvec(&RingFile {
            version: VERSION,
            samples: samples[start..].to_vec(),
        })
        .unwrap()
    }

    fn decode(bytes: &[u8]) -> Vec<PctSample> {
        match postcard::from_bytes::<RingFile>(bytes) {
            Ok(f) if f.version == VERSION => f.samples,
            _ => Vec::new(),
        }
    }

    #[test]
    fn roundtrip_preserves_samples() {
        let samples = vec![
            PctSample {
                ts_unix: 1_700_000_000,
                used_pct: 12.34,
            },
            PctSample {
                ts_unix: 1_700_000_060,
                used_pct: 47.30,
            },
            PctSample {
                ts_unix: 1_700_000_120,
                used_pct: 100.00,
            },
        ];
        let bytes = encode(&samples);
        let back = decode(&bytes);
        assert_eq!(back, samples);
    }

    #[test]
    fn bad_bytes_decode_empty() {
        assert!(decode(b"not-a-postcard-blob").is_empty());
    }

    #[test]
    fn bad_version_decodes_empty() {
        let other = RingFile {
            version: VERSION.wrapping_add(99),
            samples: vec![PctSample {
                ts_unix: 1,
                used_pct: 1.0,
            }],
        };
        let bytes = postcard::to_allocvec(&other).unwrap();
        assert!(decode(&bytes).is_empty());
    }

    #[test]
    fn truncated_decodes_empty() {
        assert!(decode(&[0u8; 4]).is_empty());
    }

    #[test]
    fn encode_drops_oldest_when_over_cap() {
        let mut samples = Vec::new();
        for i in 0..(MAX_SAMPLES + 10) {
            samples.push(PctSample {
                ts_unix: i as u64,
                used_pct: i as f64 / 10.0,
            });
        }
        let bytes = encode(&samples);
        let back = decode(&bytes);
        assert_eq!(back.len(), MAX_SAMPLES);
        assert_eq!(back.last().unwrap().ts_unix, (MAX_SAMPLES + 10 - 1) as u64);
    }
}
