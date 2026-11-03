pub mod generated {
    include!("../../generated/rust/airdesk_generated.rs");
}

pub mod movement;
pub mod packed;

pub use generated::air_desk::protocol as fb;
pub use movement::{PackedMovementError, PackedMovementFrame};
pub use packed::{PackedError, PackedFrame, HEADER_BYTES};
