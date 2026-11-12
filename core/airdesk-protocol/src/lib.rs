//! Shared ADFP wire constants and compatibility checks.
//!
//! The existing protocol crate remains the reference implementation during
//! migration. This crate is additive and does not yet own codec bytes.

pub const ADFP_FILE_IDENTIFIER: &str = "ADEN";
pub const ADFP_VERSION: u32 = 1;
pub const MAX_ENVELOPE_BYTES: usize = 1024 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CompatibilityError {
    WrongFileIdentifier,
    UnsupportedVersion,
    Oversized,
}

pub fn validate_compatibility(
    file_identifier: &str,
    version: u32,
    byte_len: usize,
) -> Result<(), CompatibilityError> {
    if file_identifier != ADFP_FILE_IDENTIFIER {
        return Err(CompatibilityError::WrongFileIdentifier);
    }
    if version != ADFP_VERSION {
        return Err(CompatibilityError::UnsupportedVersion);
    }
    if byte_len > MAX_ENVELOPE_BYTES {
        return Err(CompatibilityError::Oversized);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_current_wire_contract() {
        assert_eq!(
            validate_compatibility(ADFP_FILE_IDENTIFIER, ADFP_VERSION, 128),
            Ok(())
        );
    }

    #[test]
    fn rejects_wrong_identifier_version_and_size() {
        assert_eq!(
            validate_compatibility("NOPE", ADFP_VERSION, 128),
            Err(CompatibilityError::WrongFileIdentifier)
        );
        assert_eq!(
            validate_compatibility(ADFP_FILE_IDENTIFIER, ADFP_VERSION + 1, 128),
            Err(CompatibilityError::UnsupportedVersion)
        );
        assert_eq!(
            validate_compatibility(ADFP_FILE_IDENTIFIER, ADFP_VERSION, MAX_ENVELOPE_BYTES + 1),
            Err(CompatibilityError::Oversized)
        );
    }
}
