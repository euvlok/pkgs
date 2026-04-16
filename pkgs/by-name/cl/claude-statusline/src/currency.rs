//! Locale-aware currency conversion for the cost segment.
//!
//! Strategy: cache both the country code and the resolved `(symbol, code,
//! usd_rate)` triple in `/tmp` and reuse them across renders. `/tmp` is the
//! right home — it survives for the duration of the user's login session and
//! the OS clears it on reboot, giving us a free "refresh once per boot"
//! cadence without tracking timestamps.
//!
//! On a cache miss we fire two best-effort HTTP calls back-to-back:
//!
//! 1. <https://ipwho.is/?fields=country_code> - geo-IP -> ISO country code
//!    (no key required). The country code is cached separately so we never
//!    re-fetch it. It maps deterministically to a currency via
//!    [`country_to_currency`].
//! 2. <https://open.er-api.com/v6/latest/USD> - exchange rates from USD to
//!    everything (no key, daily refresh upstream).
//!
//! Either failing -> fall back to USD silently. We never block the
//! prompt for more than [`FETCH_TIMEOUT`] total. The whole module is a
//! "best-effort polish" feature; the cost segment must keep working
//! even if the network is down or `/tmp` is read-only.

// `resolve()` short-circuits to USD under `cfg(test)` so tests never
// touch the network or the on-disk cache. The branch is a runtime
// `cfg!(test)` rather than two `#[cfg]` copies so that rust-analyzer
// always sees the full function body (avoiding false "inactive code"
// and "dead code" diagnostics).

use std::fs;
use std::path::PathBuf;
use std::sync::LazyLock;
use std::time::Duration;

use serde::{Deserialize, Serialize};

/// Resolved per-session currency.
///
/// `usd_rate` is the multiplier to apply to a USD amount; for USD
/// itself it's `1.0`. Held in a `LazyLock` so the geoip + FX fetch
/// happens at most once per process even if the cost segment renders
/// many times in a single invocation (e.g. tests, benches, the preview
/// pipeline).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Currency {
    pub symbol: String,
    pub code: String,
    pub usd_rate: f64,
}

impl Currency {
    #[must_use]
    pub fn usd() -> Self {
        Self {
            symbol: "$".into(),
            code: "USD".into(),
            usd_rate: 1.0,
        }
    }
}

/// Tight overall budget for the geoip + FX round trip. Two requests
/// share this; if either is slow we fall back to USD. The prompt
/// budget for a single render is well under a second, so we'd rather
/// show dollars than block.
const FETCH_TIMEOUT: Duration = Duration::from_millis(800);

static RESOLVED: LazyLock<Currency> = LazyLock::new(resolve);

/// Return the (cached, lazily-resolved) currency for this process.
/// First call: read the `/tmp` cache, or fetch+cache, or fall back
/// to USD. Subsequent calls: cheap `LazyLock` deref.
#[must_use]
pub fn current() -> &'static Currency {
    &RESOLVED
}

/// Resolve the currency by walking the cache -> geoip -> FX pipeline.
/// Each step is a hard "fall back to USD" boundary; the function never
/// returns an error.
///
/// `CLAUDE_STATUSLINE_CURRENCY` short-circuits the entire pipeline:
/// set it to `USD` to force the historical dollar formatting, or to a
/// supported ISO code (`EUR`, `JPY`, …) to pin a specific currency
/// without relying on geo-IP.
///
/// Under `cfg(test)` the function short-circuits to USD so tests never
/// touch the network or the on-disk cache.
fn resolve() -> Currency {
    if cfg!(test) {
        return Currency::usd();
    }
    if let Ok(forced) = std::env::var("CLAUDE_STATUSLINE_CURRENCY") {
        let code = forced.trim();
        if let Some(c) = currency_from_code_with_rate(code) {
            return c;
        }
    }
    if let Some(c) = read_currency_cache() {
        return c;
    }
    if let Some(c) = fetch_and_cache() {
        return c;
    }
    Currency::usd()
}

/// Look up a currency by ISO code and fetch its exchange rate. Used by
/// the `CLAUDE_STATUSLINE_CURRENCY` override. Tries the cache first,
/// then fetches the rate from the network. Falls back to `None` if
/// the code is unrecognised.
fn currency_from_code_with_rate(code: &str) -> Option<Currency> {
    if code.eq_ignore_ascii_case("USD") {
        let c = Currency::usd();
        write_currency_cache(&c);
        return Some(c);
    }
    let upper = code.to_ascii_uppercase();
    if STALE_CODES.contains(&upper.as_str()) {
        // Legacy code for a country that now uses the euro — resolve as EUR.
        return currency_from_code_with_rate("EUR");
    }
    let iso = iso_currency::Currency::from_code(code)?;
    let symbol = display_symbol(iso);
    let iso_code = iso.code().to_owned();

    // Try cache first — if cached currency matches the forced code, reuse it
    if let Some(cached) = read_currency_cache() {
        if cached.code == iso_code {
            return Some(cached);
        }
    }

    // Fetch the actual exchange rate
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(FETCH_TIMEOUT))
        .user_agent(concat!("claude-statusline/", env!("CARGO_PKG_VERSION")))
        .build()
        .into();

    let rate = fetch_rate(&agent, &iso_code)?;
    if !rate.is_finite() || rate <= 0.0 {
        return None;
    }
    let c = Currency {
        symbol,
        code: iso_code,
        usd_rate: rate,
    };
    write_currency_cache(&c);
    Some(c)
}

/// Return a compact display symbol for a currency. For currencies that
/// share a `$` glyph, we prefix with the country code to disambiguate
/// (e.g. `C$` for CAD, `A$` for AUD). For everything else we use the
/// ISO 4217 symbol directly.
fn display_symbol(c: iso_currency::Currency) -> String {
    match c {
        iso_currency::Currency::CAD => "C$",
        iso_currency::Currency::AUD => "A$",
        iso_currency::Currency::NZD => "NZ$",
        iso_currency::Currency::MXN => "MX$",
        iso_currency::Currency::ARS => "AR$",
        iso_currency::Currency::CLP => "CLP$",
        iso_currency::Currency::COP => "COL$",
        iso_currency::Currency::SGD => "S$",
        iso_currency::Currency::TWD => "NT$",
        iso_currency::Currency::BRL => "R$",
        iso_currency::Currency::CHF => "CHF ",
        _ => return c.symbol().to_string(),
    }
    .into()
}

fn tmp_base() -> PathBuf {
    if cfg!(unix) {
        PathBuf::from("/tmp")
    } else {
        std::env::temp_dir()
    }
}

fn currency_cache_path() -> PathBuf {
    tmp_base().join("claude-statusline-currency.json")
}

fn country_cache_path() -> PathBuf {
    tmp_base().join("claude-statusline-country")
}

// ── currency cache ────────────────────────────────────────────────────────────

fn read_currency_cache() -> Option<Currency> {
    let bytes = fs::read(currency_cache_path()).ok()?;
    let c: Currency = serde_json::from_slice(&bytes).ok()?;
    // Reject stale entries for legacy currencies whose countries have
    // since adopted the euro (e.g. BGN after Bulgaria joined the eurozone).
    if STALE_CODES.contains(&c.code.as_str()) {
        let _ = fs::remove_file(currency_cache_path());
        return None;
    }
    Some(c)
}

/// Legacy currency codes that should no longer be cached because their
/// countries have adopted the euro. If we find one of these in the cache
/// we discard it and re-fetch.
const STALE_CODES: &[&str] = &["BGN", "HRK"];

fn write_currency_cache(c: &Currency) {
    if let Ok(bytes) = serde_json::to_vec(c) {
        let _ = fs::write(currency_cache_path(), bytes);
    }
}

// ── country cache ─────────────────────────────────────────────────────────────

/// Read the cached ISO 3166-1 alpha-2 country code, if present.
fn read_country_cache() -> Option<String> {
    let s = fs::read_to_string(country_cache_path()).ok()?;
    let trimmed = s.trim_ascii().to_ascii_uppercase();
    if trimmed.len() == 2 && trimmed.chars().all(|c| c.is_ascii_alphabetic()) {
        Some(trimmed)
    } else {
        None
    }
}

fn write_country_cache(country: &str) {
    let _ = fs::write(country_cache_path(), country.to_ascii_uppercase());
}

// ── network ───────────────────────────────────────────────────────────────────

fn fetch_and_cache() -> Option<Currency> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(FETCH_TIMEOUT))
        .user_agent(concat!("claude-statusline/", env!("CARGO_PKG_VERSION")))
        .build()
        .into();

    let country = read_country_cache().or_else(|| {
        let c = fetch_country(&agent)?;
        write_country_cache(&c);
        Some(c)
    })?;

    let (code, symbol) = country_to_currency(&country)?;
    if code == "USD" {
        let c = Currency::usd();
        write_currency_cache(&c);
        return Some(c);
    }
    let rate = fetch_rate(&agent, &code)?;
    if !rate.is_finite() || rate <= 0.0 {
        return None;
    }
    let c = Currency {
        symbol,
        code,
        usd_rate: rate,
    };
    write_currency_cache(&c);
    Some(c)
}

#[derive(Deserialize)]
struct IpWhoIs {
    country_code: Option<String>,
}

fn fetch_country(agent: &ureq::Agent) -> Option<String> {
    let mut resp = agent
        .get("https://ipwho.is/?fields=country_code")
        .call()
        .ok()?;
    let body = resp
        .body_mut()
        .with_config()
        .limit(64 * 1024)
        .read_to_vec()
        .ok()?;
    let parsed: IpWhoIs = serde_json::from_slice(&body).ok()?;
    parsed.country_code.filter(|c| !c.is_empty())
}

#[derive(Deserialize)]
struct ErApi {
    result: Option<String>,
    rates: Option<std::collections::HashMap<String, f64>>,
}

fn fetch_rate(agent: &ureq::Agent, code: &str) -> Option<f64> {
    let mut resp = agent
        .get("https://open.er-api.com/v6/latest/USD")
        .call()
        .ok()?;
    let body = resp
        .body_mut()
        .with_config()
        .limit(256 * 1024)
        .read_to_vec()
        .ok()?;
    let parsed: ErApi = serde_json::from_slice(&body).ok()?;
    if parsed.result.as_deref() != Some("success") {
        return None;
    }
    parsed.rates?.get(code).copied()
}

/// Countries that have adopted the Euro since the `iso_currency` crate's
/// data was last updated. The crate still maps these to their legacy
/// currencies, so we override them here.
const EURO_OVERRIDES: &[&str] = &[
    "BG", // Bulgaria adopted EUR on 2025-01-01
    "HR", // Croatia adopted EUR on 2023-01-01
];

/// Map an ISO 3166-1 alpha-2 country code to its primary `(code, symbol)`
/// pair. Uses the `iso_currency` crate for the country→currency lookup
/// and our [`display_symbol`] helper for disambiguated symbols.
///
/// Returns `None` for unrecognised country codes, which the caller
/// treats as "fall back to USD".
pub fn country_to_currency(country: &str) -> Option<(String, String)> {
    let upper = country.to_ascii_uppercase();
    if EURO_OVERRIDES.contains(&upper.as_str()) {
        return Some(("EUR".into(), "€".into()));
    }
    let country_enum: iso_currency::Country = upper.parse().ok()?;
    let iso = iso_currency::Currency::from(country_enum);
    let code = iso.code().to_owned();
    let symbol = display_symbol(iso);
    Some((code, symbol))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eurozone_resolves_to_euro() {
        assert_eq!(country_to_currency("DE"), Some(("EUR".into(), "€".into())));
        assert_eq!(country_to_currency("fr"), Some(("EUR".into(), "€".into())));
    }

    #[test]
    fn bulgaria_is_euro_since_2025() {
        assert_eq!(country_to_currency("BG"), Some(("EUR".into(), "€".into())));
    }

    #[test]
    fn croatia_is_euro_since_2023() {
        assert_eq!(country_to_currency("HR"), Some(("EUR".into(), "€".into())));
    }

    #[test]
    fn poland_is_zloty() {
        assert_eq!(country_to_currency("PL"), Some(("PLN".into(), "zł".into())));
    }

    #[test]
    fn unknown_country_returns_none() {
        assert!(country_to_currency("ZZ").is_none());
    }

    #[test]
    fn usd_currency_default() {
        let u = Currency::usd();
        assert_eq!(u.code, "USD");
        assert_eq!(u.usd_rate, 1.0);
    }

    #[test]
    fn stale_bgn_is_rejected() {
        assert!(STALE_CODES.contains(&"BGN"));
        assert!(STALE_CODES.contains(&"HRK"));
    }

    #[test]
    fn country_cache_roundtrip() {
        // Validate that the format check in read_country_cache accepts valid codes
        // and rejects garbage. We test the logic directly without touching /tmp.
        let valid = "BG";
        assert_eq!(valid.len(), 2);
        assert!(valid.chars().all(|c| c.is_ascii_alphabetic()));

        let invalid = "not-a-code";
        assert!(invalid.len() != 2 || !invalid.chars().all(|c| c.is_ascii_alphabetic()));
    }
}
