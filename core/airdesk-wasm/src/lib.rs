//! Browser-safe subset of the shared core.
//!
//! Native filesystem, network, PTY and platform APIs must never be imported
//! here. P3-07 exposes only a non-authoritative ABI smoke surface.

use airdesk_protocol::movement::{OneEuroFilter, OneEuroParameters};
use wasm_bindgen::prelude::*;

pub use airdesk_core::{abi_version, is_abi_compatible, CORE_ABI_VERSION};
pub use airdesk_protocol::{ADFP_FILE_IDENTIFIER, ADFP_VERSION, MAX_ENVELOPE_BYTES};

/// Return the shared-core ABI version.
#[wasm_bindgen]
pub fn core_abi_version() -> u32 {
    CORE_ABI_VERSION
}

/// Check whether a caller-required ABI version is compatible with this core.
#[wasm_bindgen]
pub fn core_is_abi_compatible(required: u32) -> bool {
    is_abi_compatible(required)
}

/// Non-authoritative label used by the flag-gated browser smoke path.
#[wasm_bindgen]
pub fn core_smoke_label() -> String {
    format!("airdesk-core/{}", CORE_ABI_VERSION)
}

/// Browser one-euro filter used only when the P3-08 movement flag selects core.
#[wasm_bindgen]
pub struct CoreOneEuroFilter {
    inner: OneEuroFilter,
}

#[wasm_bindgen]
impl CoreOneEuroFilter {
    #[wasm_bindgen(constructor)]
    pub fn new(min_cutoff: f64, beta: f64, d_cutoff: f64) -> Result<CoreOneEuroFilter, JsValue> {
        let inner = OneEuroFilter::new(OneEuroParameters {
            min_cutoff,
            beta,
            d_cutoff,
        })
        .map_err(|error| JsValue::from_str(&error.to_string()))?;
        Ok(Self { inner })
    }

    pub fn reset(&mut self) {
        self.inner.reset();
    }

    /// Return `[x, y]`; JS wrappers map the pair to a point object.
    pub fn filter(&mut self, x: f64, y: f64, timestamp: f64) -> Result<Vec<f64>, JsValue> {
        let (x, y) = self
            .inner
            .filter(x, y, timestamp)
            .map_err(|error| JsValue::from_str(&error.to_string()))?;
        Ok(vec![x, y])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exposes_browser_safe_contract() {
        assert_eq!(core_abi_version(), abi_version());
        assert_eq!(MAX_ENVELOPE_BYTES, 1024 * 1024);
        assert_eq!(ADFP_VERSION, 1);
    }

    #[test]
    fn movement_filter_is_browser_safe_and_seeded() {
        let mut filter = CoreOneEuroFilter::new(1.0, 160.0, 1.0).unwrap();
        assert_eq!(filter.filter(0.25, 0.75, 0.0).unwrap(), vec![0.25, 0.75]);
        let filtered = filter.filter(0.3, 0.7, 1.0 / 120.0).unwrap();
        assert!(filtered.iter().all(|value| value.is_finite()));
        filter.reset();
        assert_eq!(filter.filter(0.4, 0.6, 1.0).unwrap(), vec![0.4, 0.6]);
    }

    #[test]
    fn smoke_surface_is_non_authoritative_and_versioned() {
        assert_eq!(
            core_smoke_label(),
            format!("airdesk-core/{CORE_ABI_VERSION}")
        );
        assert!(core_is_abi_compatible(CORE_ABI_VERSION));
        assert!(!core_is_abi_compatible(CORE_ABI_VERSION + 1));
    }
}
