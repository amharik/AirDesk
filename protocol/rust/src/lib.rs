pub mod generated {
    include!("../../generated/rust/airdesk_generated.rs");
}

pub mod packed;

pub use generated::air_desk::protocol as fb;
pub use packed::{PackedError, PackedFrame, HEADER_BYTES};
