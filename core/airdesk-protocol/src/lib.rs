//! Shared ADFP wire constants, packed input codecs and movement filtering.
//!
//! The legacy `protocol/rust` crate re-exports these items so existing callers
//! keep their import paths while the implementation moves into the shared core.

#[allow(clippy::all, clippy::pedantic, clippy::nursery)]
pub mod generated {
    include!("../../../protocol/generated/rust/airdesk_generated.rs");
}

pub use generated::air_desk::protocol as fb;

pub mod envelope;
pub mod movement;
pub mod packed;
pub mod resource;

pub use envelope::{
    decode, encode_control, encode_input, AdfpControlMessage, AdfpEnvelope, AdfpError, AdfpHeader,
    AdfpInputEvent, AdfpPayload, FILE_IDENTIFIER, MAX_HEADER_STRING_BYTES,
};
pub use movement::{
    OneEuroFilter, OneEuroFilterError, OneEuroParameters, PackedMovementError, PackedMovementFrame,
    ONE_EURO_MINIMUM_DELTA_TIME,
};
pub use packed::{PackedError, PackedFrame, HEADER_BYTES};
pub use resource::{
    decode_compound_request, decode_compound_result, decode_read_result, validate_blob,
    validate_compound_request, validate_compound_result, BlobHandleData, CompoundRequest,
    CompoundResult, QidData, ReadResult, ResourceError, ResourceStatData, BLAKE3_DIGEST_BYTES,
    BLOB_HANDLE_VERSION, RESOURCE_INLINE_LIMIT, RESOURCE_MAX_PATH_SEGMENTS,
};

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
