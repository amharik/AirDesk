//! Browser-safe subset of the shared core.
//!
//! Native filesystem, network, PTY and platform APIs must never be imported
//! here. The first wasm-bindgen exports arrive with P3-07.

pub use airdesk_core::{abi_version, is_abi_compatible, CORE_ABI_VERSION};
pub use airdesk_protocol::{ADFP_FILE_IDENTIFIER, ADFP_VERSION, MAX_ENVELOPE_BYTES};

pub fn core_abi_version() -> u32 {
    CORE_ABI_VERSION
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
}
