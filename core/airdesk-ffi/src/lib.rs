//! UniFFI boundary for the non-authoritative shared-core smoke API.
//!
//! P3-06 keeps this surface deliberately small. Product filesystem, network,
//! PTY, pairing and display paths remain in their existing implementations
//! until P3-08 and its rollback gate.

uniffi::setup_scaffolding!();

pub use airdesk_core::{abi_version, is_abi_compatible, CORE_ABI_VERSION};
pub use airdesk_protocol::{
    validate_compatibility, CompatibilityError, ADFP_FILE_IDENTIFIER, ADFP_VERSION,
    MAX_ENVELOPE_BYTES,
};

/// Return the shared-core ABI version.
#[uniffi::export]
pub fn core_abi_version() -> u32 {
    CORE_ABI_VERSION
}

/// Check whether a caller-required ABI version is compatible with this core.
#[uniffi::export]
pub fn core_is_abi_compatible(required: u32) -> bool {
    is_abi_compatible(required)
}

/// Non-authoritative label used by the flag-gated iOS and Android smoke calls.
#[uniffi::export]
pub fn core_smoke_label() -> String {
    format!("airdesk-core/{}", CORE_ABI_VERSION)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reexports_core_and_protocol_contract() {
        assert_eq!(core_abi_version(), abi_version());
        assert_eq!(ADFP_FILE_IDENTIFIER, "ADEN");
        assert_eq!(
            validate_compatibility(ADFP_FILE_IDENTIFIER, ADFP_VERSION, 0),
            Ok(())
        );
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
