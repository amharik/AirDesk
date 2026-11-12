//! Browser-safe subset of the shared core.
//!
//! Native filesystem, network, PTY and platform APIs must never be imported
//! here. P3-07 exposes only a non-authoritative ABI smoke surface.

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
    fn smoke_surface_is_non_authoritative_and_versioned() {
        assert_eq!(
            core_smoke_label(),
            format!("airdesk-core/{CORE_ABI_VERSION}")
        );
        assert!(core_is_abi_compatible(CORE_ABI_VERSION));
        assert!(!core_is_abi_compatible(CORE_ABI_VERSION + 1));
    }
}
