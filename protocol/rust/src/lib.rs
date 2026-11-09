pub mod generated {
    include!("../../generated/rust/airdesk_generated.rs");
}

pub mod adfp;
pub mod movement;
pub mod packed;
pub mod resource;

pub use generated::air_desk::protocol as fb;
pub use adfp::{AdfpControlMessage, AdfpEnvelope, AdfpError, AdfpHeader, AdfpInputEvent, AdfpPayload};
pub use movement::{PackedMovementError, PackedMovementFrame};
pub use resource::{
    decode_compound_request, decode_compound_result, decode_read_result, validate_blob,
    validate_compound_request, validate_compound_result, BlobHandleData, CompoundRequest,
    CompoundResult, QidData, ReadResult, ResourceError, ResourceStatData, BLAKE3_DIGEST_BYTES,
    BLOB_HANDLE_VERSION, RESOURCE_INLINE_LIMIT, RESOURCE_MAX_PATH_SEGMENTS,
};
pub use packed::{PackedError, PackedFrame, HEADER_BYTES};
