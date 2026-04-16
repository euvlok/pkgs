//! Persistent `(timestamp, used_pct)` sample ring.
//!
//! The pace segment's entire persistent state: a tiny binary file in the
//! platform cache directory, capped at a single 5h window's worth of
//! samples. Rewritten atomically on every render.
//!
//! Format
//!
//! ```text
//! [magic: 8 B = b"clstpace"]
//! [version: u32 LE]
//! [sample_count: u32 LE]
//! [sample_count × (ts_unix: u64 LE, used_pct_bp: u32 LE)]
//! ```
//!
//! `used_pct_bp` stores the percentage in basis points (1% = 100), which
//! fits `0..=10000` cleanly in 32 bits with plenty of headroom for the
//! ">100%" readings Anthropic occasionally surfaces during corrections.

use std::fs;
use std::io::Write as _;
use std::path::PathBuf;

pub(crate) const MAGIC: &[u8; 8] = b"clstpace";
pub(crate) const VERSION: u32 = 1;
const HEADER_BYTES: usize = 16;
const SAMPLE_BYTES: usize = 12;

/// Upper bound on in-memory + on-disk sample count.
///
/// One 5h window at a realistic render cadence fits in well under this,
/// but we cap to keep the file bounded when the user is running renders
/// in a tight loop.
pub const MAX_SAMPLES: usize = 256;

/// A single observation. `used_pct` is a raw percentage (not basis
/// points); the basis-point encoding is a storage detail.
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct PctSample {
    pub ts_unix: u64,
    pub used_pct: f64,
}

/// Resolve the cache file path. `None` when the platform cache dir is
/// unavailable (e.g. $HOME missing in some CI sandboxes).
fn ring_path() -> Option<PathBuf> {
    Some(
        dirs::cache_dir()?
            .join("claude-statusline")
            .join("pace")
            .join("samples.bin"),
    )
}

/// Load the ring, returning an empty vector on any failure (missing
/// file, magic/version mismatch, truncated). The caller treats that as
/// "start fresh".
#[must_use]
pub fn load_ring() -> Vec<PctSample> {
    ring_path()
        .and_then(|p| fs::read(p).ok())
        .map(|bytes| decode(&bytes))
        .unwrap_or_default()
}

/// Atomically replace the cache file with the given samples. Silent on
/// I/O failure — the pace segment degrades gracefully to a warmup state
/// next render.
pub fn persist_ring(samples: &[PctSample]) {
    let Some(path) = ring_path() else { return };
    let Some(parent) = path.parent() else { return };
    if fs::create_dir_all(parent).is_err() {
        return;
    }
    let bytes = encode(samples);
    let Ok(mut tmp) = tempfile::NamedTempFile::new_in(parent) else {
        return;
    };
    if tmp.write_all(&bytes).is_err() {
        return;
    }
    let _ = tmp.persist(&path);
}

fn encode(samples: &[PctSample]) -> Vec<u8> {
    let count = samples.len().min(MAX_SAMPLES);
    // Keep the newest samples if we're over the cap.
    let start = samples.len().saturating_sub(count);
    let mut buf = Vec::with_capacity(HEADER_BYTES + count * SAMPLE_BYTES);
    buf.extend_from_slice(MAGIC);
    buf.extend_from_slice(&VERSION.to_le_bytes());
    buf.extend_from_slice(&(count as u32).to_le_bytes());
    for s in &samples[start..] {
        buf.extend_from_slice(&s.ts_unix.to_le_bytes());
        let bp = pct_to_bp(s.used_pct);
        buf.extend_from_slice(&bp.to_le_bytes());
    }
    buf
}

fn decode(bytes: &[u8]) -> Vec<PctSample> {
    if bytes.len() < HEADER_BYTES {
        return Vec::new();
    }
    if &bytes[0..8] != MAGIC {
        return Vec::new();
    }
    let version = u32::from_le_bytes(match bytes[8..12].try_into() {
        Ok(a) => a,
        Err(_) => return Vec::new(),
    });
    if version != VERSION {
        return Vec::new();
    }
    let count = u32::from_le_bytes(match bytes[12..16].try_into() {
        Ok(a) => a,
        Err(_) => return Vec::new(),
    }) as usize;
    let expected = HEADER_BYTES + count * SAMPLE_BYTES;
    if bytes.len() < expected {
        return Vec::new();
    }
    let mut out = Vec::with_capacity(count);
    for i in 0..count {
        let off = HEADER_BYTES + i * SAMPLE_BYTES;
        let ts = u64::from_le_bytes(match bytes[off..off + 8].try_into() {
            Ok(a) => a,
            Err(_) => return Vec::new(),
        });
        let bp = u32::from_le_bytes(match bytes[off + 8..off + 12].try_into() {
            Ok(a) => a,
            Err(_) => return Vec::new(),
        });
        out.push(PctSample {
            ts_unix: ts,
            used_pct: bp_to_pct(bp),
        });
    }
    out
}

fn pct_to_bp(pct: f64) -> u32 {
    if !pct.is_finite() || pct < 0.0 {
        return 0;
    }
    let scaled = (pct * 100.0).round();
    if scaled >= u32::MAX as f64 {
        u32::MAX
    } else {
        scaled as u32
    }
}

fn bp_to_pct(bp: u32) -> f64 {
    f64::from(bp) / 100.0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_preserves_samples() {
        let samples = vec![
            PctSample { ts_unix: 1_700_000_000, used_pct: 12.34 },
            PctSample { ts_unix: 1_700_000_060, used_pct: 47.30 },
            PctSample { ts_unix: 1_700_000_120, used_pct: 100.00 },
        ];
        let bytes = encode(&samples);
        let back = decode(&bytes);
        assert_eq!(back.len(), samples.len());
        for (a, b) in samples.iter().zip(back.iter()) {
            assert_eq!(a.ts_unix, b.ts_unix);
            assert!((a.used_pct - b.used_pct).abs() < 1e-6);
        }
    }

    #[test]
    fn bad_magic_decodes_empty() {
        let bytes = b"notthemgc\0\0\0\0\0\0\0\0";
        assert!(decode(bytes).is_empty());
    }

    #[test]
    fn bad_version_decodes_empty() {
        let mut bytes = Vec::new();
        bytes.extend_from_slice(MAGIC);
        bytes.extend_from_slice(&9999u32.to_le_bytes());
        bytes.extend_from_slice(&0u32.to_le_bytes());
        assert!(decode(&bytes).is_empty());
    }

    #[test]
    fn truncated_decodes_empty() {
        let bytes = [0u8; 4];
        assert!(decode(&bytes).is_empty());
    }

    #[test]
    fn encode_drops_oldest_when_over_cap() {
        let mut samples = Vec::new();
        for i in 0..(MAX_SAMPLES + 10) {
            samples.push(PctSample { ts_unix: i as u64, used_pct: i as f64 / 10.0 });
        }
        let bytes = encode(&samples);
        let back = decode(&bytes);
        assert_eq!(back.len(), MAX_SAMPLES);
        // Newest is kept.
        assert_eq!(back.last().unwrap().ts_unix, (MAX_SAMPLES + 10 - 1) as u64);
    }

    #[test]
    fn bp_roundtrip_precision() {
        for pct in [0.0, 0.01, 12.34, 47.3, 100.0, 168.75] {
            let bp = pct_to_bp(pct);
            let back = bp_to_pct(bp);
            assert!((pct - back).abs() < 1e-6, "pct={pct} back={back}");
        }
    }

    #[test]
    fn negative_pct_encodes_to_zero() {
        assert_eq!(pct_to_bp(-5.0), 0);
    }

    #[test]
    fn non_finite_pct_encodes_to_zero() {
        assert_eq!(pct_to_bp(f64::NAN), 0);
        assert_eq!(pct_to_bp(f64::INFINITY), 0);
    }
}
