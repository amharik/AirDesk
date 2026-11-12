//! Platform-neutral AirDesk algorithms and state machines.
//!
//! This crate intentionally has no platform, filesystem, network or crypto
//! dependencies. Migrated components are additive until their fixture and
//! rollback gates pass.

pub const CORE_ABI_VERSION: u32 = 1;

pub fn abi_version() -> u32 {
    CORE_ABI_VERSION
}

pub fn is_abi_compatible(required: u32) -> bool {
    required <= CORE_ABI_VERSION
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reports_current_abi_version() {
        assert_eq!(abi_version(), 1);
    }

    #[test]
    fn accepts_known_and_rejects_future_abi() {
        assert!(is_abi_compatible(0));
        assert!(is_abi_compatible(CORE_ABI_VERSION));
        assert!(!is_abi_compatible(CORE_ABI_VERSION + 1));
    }
}
