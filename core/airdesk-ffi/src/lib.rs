//! Typed boundary for future UniFFI Swift and Kotlin bindings.
//!
//! The exported surface remains deliberately small until P3-06 adds generated
//! bindings and the platform packages.

pub use airdesk_core::{abi_version, is_abi_compatible, CORE_ABI_VERSION};
pub use airdesk_protocol::{
    validate_compatibility, CompatibilityError, ADFP_FILE_IDENTIFIER, ADFP_VERSION,
    MAX_ENVELOPE_BYTES,
};

pub fn core_abi_version() -> u32 {
    CORE_ABI_VERSION
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
}
