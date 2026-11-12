pub mod generated {
    include!("../../generated/rust/airdesk_generated.rs");
}

pub mod adfp {
    pub use airdesk_core_protocol::envelope::*;
}
pub mod movement {
    pub use airdesk_core_protocol::movement::*;
}
pub mod packed {
    pub use airdesk_core_protocol::packed::*;
}
pub mod resource {
    pub use airdesk_core_protocol::resource::*;
}

pub use airdesk_core_protocol::envelope::{
    AdfpControlMessage, AdfpEnvelope, AdfpError, AdfpHeader, AdfpInputEvent, AdfpPayload,
};
pub use airdesk_core_protocol::movement::{
    OneEuroFilter, OneEuroFilterError, OneEuroParameters, PackedMovementError, PackedMovementFrame,
    ONE_EURO_MINIMUM_DELTA_TIME,
};
pub use airdesk_core_protocol::packed::{PackedError, PackedFrame, HEADER_BYTES};
pub use airdesk_core_protocol::resource::{
    decode_compound_request, decode_compound_result, decode_read_result, validate_blob,
    validate_compound_request, validate_compound_result, BlobHandleData, CompoundRequest,
    CompoundResult, QidData, ReadResult, ResourceError, ResourceStatData, BLAKE3_DIGEST_BYTES,
    BLOB_HANDLE_VERSION, RESOURCE_INLINE_LIMIT, RESOURCE_MAX_PATH_SEGMENTS,
};
pub use generated::air_desk::protocol as fb;

#[cfg(test)]
mod compatibility_tests {
    use super::*;

    #[test]
    fn reexports_shared_core_codecs() {
        assert_eq!(
            PackedFrame::session_tag("session-1"),
            Ok(1_623_645_925_111_568_461)
        );
        assert_eq!(
            PackedMovementFrame::decode(&[
                0xa5, 0x24, 0x07, 0x00, 0x2a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x3e, 0x00, 0x00,
                0x40, 0x3f,
            ])
            .map(|frame| frame.seq),
            Ok(42)
        );
        assert_eq!(adfp::FILE_IDENTIFIER, "ADEN");
    }
}
