//! UniFFI boundary for the non-authoritative shared-core smoke API.
//!
//! P3-06 keeps this surface deliberately small. Product filesystem, network,
//! PTY, pairing and display paths remain in their existing implementations
//! until P3-08 and its rollback gate.

use std::sync::{Arc, Mutex};

use airdesk_pairing::spake2plus::{
    registration_record, ProverFinishResult, ProverSession, Spake2PlusError, Spake2PlusKeys,
    VerifierFinishResult, VerifierSession,
};
use airdesk_protocol::movement::{
    OneEuroFilter, OneEuroFilterError, OneEuroParameters, PackedMovementError, PackedMovementFrame,
};

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

#[derive(Clone, Copy, Debug, PartialEq, uniffi::Record)]
pub struct CorePoint {
    pub x: f64,
    pub y: f64,
}

#[derive(Clone, Copy, Debug, PartialEq, uniffi::Record)]
pub struct CorePackedMovement {
    pub lease_epoch_low: u16,
    pub seq: u32,
    pub x: f32,
    pub y: f32,
    pub button_mask: u8,
    pub modifiers: u8,
}

#[derive(Debug, PartialEq, thiserror::Error, uniffi::Error)]
pub enum CoreMovementError {
    #[error("invalid one-euro filter parameters")]
    InvalidParameters,
    #[error("movement input must be finite")]
    NonFiniteInput,
    #[error("invalid packed movement frame: {0}")]
    InvalidPackedFrame(String),
}

impl From<OneEuroFilterError> for CoreMovementError {
    fn from(error: OneEuroFilterError) -> Self {
        match error {
            OneEuroFilterError::InvalidParameters => Self::InvalidParameters,
            OneEuroFilterError::NonFiniteInput => Self::NonFiniteInput,
        }
    }
}

impl From<PackedMovementError> for CoreMovementError {
    fn from(error: PackedMovementError) -> Self {
        Self::InvalidPackedFrame(error.to_string())
    }
}

fn movement_lock_error<T>(_error: std::sync::PoisonError<T>) -> CoreMovementError {
    CoreMovementError::InvalidParameters
}

/// A stateful one-euro pointer filter used by the P3-08 core path.
#[derive(uniffi::Object)]
pub struct CoreOneEuroFilter {
    inner: Mutex<OneEuroFilter>,
}

#[uniffi::export]
impl CoreOneEuroFilter {
    #[uniffi::constructor]
    pub fn new(min_cutoff: f64, beta: f64, d_cutoff: f64) -> Result<Arc<Self>, CoreMovementError> {
        let filter = OneEuroFilter::new(OneEuroParameters {
            min_cutoff,
            beta,
            d_cutoff,
        })?;
        Ok(Arc::new(Self {
            inner: Mutex::new(filter),
        }))
    }

    pub fn reset(&self) -> Result<(), CoreMovementError> {
        let mut filter = self.inner.lock().map_err(movement_lock_error)?;
        filter.reset();
        Ok(())
    }

    pub fn filter(&self, x: f64, y: f64, timestamp: f64) -> Result<CorePoint, CoreMovementError> {
        let mut filter = self.inner.lock().map_err(movement_lock_error)?;
        let (x, y) = filter.filter(x, y, timestamp)?;
        Ok(CorePoint { x, y })
    }
}

/// Encode a packed movement frame with the shared core codec.
#[uniffi::export]
pub fn core_packed_movement_encode(
    frame: CorePackedMovement,
) -> Result<Vec<u8>, CoreMovementError> {
    Ok(PackedMovementFrame {
        lease_epoch_low: frame.lease_epoch_low,
        seq: frame.seq,
        x: frame.x,
        y: frame.y,
        button_mask: frame.button_mask,
        modifiers: frame.modifiers,
    }
    .encode()?
    .to_vec())
}

/// Decode a packed movement frame with the shared core codec.
#[uniffi::export]
pub fn core_packed_movement_decode(data: Vec<u8>) -> Result<CorePackedMovement, CoreMovementError> {
    let frame = PackedMovementFrame::decode(&data)?;
    Ok(CorePackedMovement {
        lease_epoch_low: frame.lease_epoch_low,
        seq: frame.seq,
        x: frame.x,
        y: frame.y,
        button_mask: frame.button_mask,
        modifiers: frame.modifiers,
    })
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreSpake2PlusError {
    #[error("{0}")]
    Invalid(String),
    #[error("confirmation mismatch")]
    ConfirmationMismatch,
}

impl From<Spake2PlusError> for CoreSpake2PlusError {
    fn from(error: Spake2PlusError) -> Self {
        match error {
            Spake2PlusError::ConfirmationMismatch => Self::ConfirmationMismatch,
            other => Self::Invalid(other.to_string()),
        }
    }
}

#[derive(Clone, uniffi::Record)]
pub struct CoreSpake2PlusKeys {
    pub k_main: Vec<u8>,
    pub k_confirm_p: Vec<u8>,
    pub k_confirm_v: Vec<u8>,
    pub k_shared: Vec<u8>,
}

#[derive(uniffi::Record)]
pub struct CoreSpake2PlusFinishResult {
    pub share_p: Vec<u8>,
    pub share_v: Vec<u8>,
    pub z: Vec<u8>,
    pub v: Vec<u8>,
    pub transcript: Vec<u8>,
    pub keys: CoreSpake2PlusKeys,
    pub confirmation: Vec<u8>,
    pub expected_confirmation: Vec<u8>,
}

#[derive(Clone, uniffi::Record)]
pub struct CoreSpake2PlusVerifierResponse {
    pub share_v: Vec<u8>,
    pub confirmation: Vec<u8>,
    pub expected_confirmation: Vec<u8>,
}

fn keys_record(keys: &Spake2PlusKeys) -> CoreSpake2PlusKeys {
    CoreSpake2PlusKeys {
        k_main: keys.k_main.to_vec(),
        k_confirm_p: keys.k_confirm_p.to_vec(),
        k_confirm_v: keys.k_confirm_v.to_vec(),
        k_shared: keys.k_shared.to_vec(),
    }
}

fn prover_finish_record(result: ProverFinishResult) -> CoreSpake2PlusFinishResult {
    CoreSpake2PlusFinishResult {
        share_p: result.share_p.to_vec(),
        share_v: result.share_v.to_vec(),
        z: result.z.to_vec(),
        v: result.v.to_vec(),
        transcript: result.transcript.to_vec(),
        keys: keys_record(&result.keys),
        confirmation: result.confirmation.to_vec(),
        expected_confirmation: result.expected_confirmation.to_vec(),
    }
}

fn verifier_finish_record(result: VerifierFinishResult) -> CoreSpake2PlusFinishResult {
    CoreSpake2PlusFinishResult {
        share_p: result.share_p.to_vec(),
        share_v: result.share_v.to_vec(),
        z: result.z.to_vec(),
        v: result.v.to_vec(),
        transcript: result.transcript.to_vec(),
        keys: keys_record(&result.keys),
        confirmation: result.confirmation.to_vec(),
        expected_confirmation: result.expected_confirmation.to_vec(),
    }
}

fn lock_error<T>(_error: std::sync::PoisonError<T>) -> CoreSpake2PlusError {
    CoreSpake2PlusError::Invalid("session lock poisoned".into())
}

/// Build the verifier registration point `L = w1*P`.
#[uniffi::export]
pub fn core_spake2plus_registration_record(w1: Vec<u8>) -> Result<Vec<u8>, CoreSpake2PlusError> {
    Ok(registration_record(&w1)?.to_vec())
}

/// Non-authoritative stateful prover preview. Product use remains behind P3-08.
#[derive(uniffi::Object)]
pub struct CoreSpake2PlusProverSession {
    inner: Mutex<ProverSession>,
}

#[uniffi::export]
impl CoreSpake2PlusProverSession {
    #[uniffi::constructor]
    pub fn new(
        context: Vec<u8>,
        id_prover: Vec<u8>,
        id_verifier: Vec<u8>,
        w0: Vec<u8>,
        w1: Vec<u8>,
    ) -> Result<Arc<Self>, CoreSpake2PlusError> {
        let session = ProverSession::new(&context, &id_prover, &id_verifier, &w0, &w1)
            .map_err(CoreSpake2PlusError::from)?;
        Ok(Arc::new(Self {
            inner: Mutex::new(session),
        }))
    }

    pub fn start(&self) -> Result<Vec<u8>, CoreSpake2PlusError> {
        let mut session = self.inner.lock().map_err(lock_error)?;
        Ok(session.start()?.to_vec())
    }

    pub fn finish(
        &self,
        share_v: Vec<u8>,
        confirmation_v: Vec<u8>,
    ) -> Result<CoreSpake2PlusFinishResult, CoreSpake2PlusError> {
        let mut session = self.inner.lock().map_err(lock_error)?;
        let result = session.finish(&share_v, &confirmation_v)?;
        Ok(prover_finish_record(result))
    }
}

/// Non-authoritative stateful verifier preview. Product use remains behind P3-08.
#[derive(uniffi::Object)]
pub struct CoreSpake2PlusVerifierSession {
    inner: Mutex<VerifierSession>,
}

#[uniffi::export]
impl CoreSpake2PlusVerifierSession {
    #[uniffi::constructor]
    pub fn new(
        context: Vec<u8>,
        id_prover: Vec<u8>,
        id_verifier: Vec<u8>,
        w0: Vec<u8>,
        l: Vec<u8>,
    ) -> Result<Arc<Self>, CoreSpake2PlusError> {
        let session = VerifierSession::new(&context, &id_prover, &id_verifier, &w0, &l)
            .map_err(CoreSpake2PlusError::from)?;
        Ok(Arc::new(Self {
            inner: Mutex::new(session),
        }))
    }

    pub fn respond(
        &self,
        share_p: Vec<u8>,
    ) -> Result<CoreSpake2PlusVerifierResponse, CoreSpake2PlusError> {
        let mut session = self.inner.lock().map_err(lock_error)?;
        let response = session.respond(&share_p)?;
        Ok(CoreSpake2PlusVerifierResponse {
            share_v: response.share_v.to_vec(),
            confirmation: response.confirmation.to_vec(),
            expected_confirmation: response.expected_confirmation.to_vec(),
        })
    }

    pub fn finish(
        &self,
        confirmation_p: Vec<u8>,
    ) -> Result<CoreSpake2PlusFinishResult, CoreSpake2PlusError> {
        let mut session = self.inner.lock().map_err(lock_error)?;
        let result = session.finish(&confirmation_p)?;
        Ok(verifier_finish_record(result))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SPAKE2PLUS_FIXTURE: &str =
        include_str!("../../../protocol/fixtures/spake2plus-p256-rfc9383.json");

    #[derive(serde::Deserialize)]
    struct Spake2PlusVector {
        context: String,
        #[serde(rename = "idProver")]
        id_prover: String,
        #[serde(rename = "idVerifier")]
        id_verifier: String,
        w0: String,
        w1: String,
        #[serde(rename = "L")]
        l: String,
    }

    fn hex(value: &str) -> Vec<u8> {
        fn nibble(byte: u8) -> u8 {
            match byte {
                b'0'..=b'9' => byte - b'0',
                b'a'..=b'f' => byte - b'a' + 10,
                b'A'..=b'F' => byte - b'A' + 10,
                _ => panic!("invalid hex digit"),
            }
        }
        assert_eq!(value.len() % 2, 0);
        let bytes = value.as_bytes();
        (0..bytes.len())
            .step_by(2)
            .map(|index| (nibble(bytes[index]) << 4) | nibble(bytes[index + 1]))
            .collect()
    }

    fn spake2plus_vector() -> Spake2PlusVector {
        serde_json::from_str(SPAKE2PLUS_FIXTURE).expect("valid SPAKE2+ fixture")
    }

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

    #[test]
    fn movement_exports_match_shared_fixtures() {
        let filter = CoreOneEuroFilter::new(1.0, 160.0, 1.0).unwrap();
        assert_eq!(
            filter.filter(0.25, 0.75, 0.0).unwrap(),
            CorePoint { x: 0.25, y: 0.75 }
        );
        let filtered = filter.filter(0.3, 0.7, 1.0 / 120.0).unwrap();
        assert!(filtered.x.is_finite() && filtered.y.is_finite());
        assert_eq!(
            CoreOneEuroFilter::new(0.0, 160.0, 1.0).err(),
            Some(CoreMovementError::InvalidParameters)
        );

        let frame = CorePackedMovement {
            lease_epoch_low: 7,
            seq: 42,
            x: 0.25,
            y: 0.75,
            button_mask: 1,
            modifiers: 1,
        };
        let bytes = core_packed_movement_encode(frame).unwrap();
        assert_eq!(bytes, hex("a52407002a0000000000803e0000403f"),);
        assert_eq!(core_packed_movement_decode(bytes).unwrap(), frame);
    }

    #[test]
    fn spake2plus_preview_matches_registration_vector_and_round_trips() {
        let vector = spake2plus_vector();
        let w0 = hex(&vector.w0);
        let w1 = hex(&vector.w1);
        let l = hex(&vector.l);
        let context = vector.context.into_bytes();
        let id_prover = vector.id_prover.into_bytes();
        let id_verifier = vector.id_verifier.into_bytes();

        assert_eq!(core_spake2plus_registration_record(w1.clone()).unwrap(), l);

        let prover = CoreSpake2PlusProverSession::new(
            context.clone(),
            id_prover.clone(),
            id_verifier.clone(),
            w0.clone(),
            w1,
        )
        .unwrap();
        let verifier =
            CoreSpake2PlusVerifierSession::new(context, id_prover, id_verifier, w0, l).unwrap();

        let share_p = prover.start().unwrap();
        let response = verifier.respond(share_p).unwrap();
        let prover_result = prover
            .finish(response.share_v.clone(), response.confirmation.clone())
            .unwrap();
        let verifier_result = verifier.finish(prover_result.confirmation.clone()).unwrap();

        assert_eq!(prover_result.share_v, response.share_v);
        assert_eq!(
            prover_result.transcript.as_slice(),
            verifier_result.transcript.as_slice()
        );
        assert_eq!(prover_result.keys.k_main, verifier_result.keys.k_main);
        assert_eq!(
            prover_result.keys.k_confirm_p,
            verifier_result.keys.k_confirm_p
        );
        assert_eq!(
            prover_result.keys.k_confirm_v,
            verifier_result.keys.k_confirm_v
        );
        assert_eq!(prover_result.keys.k_shared, verifier_result.keys.k_shared);
        assert_eq!(prover_result.expected_confirmation, response.confirmation);
    }

    #[test]
    fn spake2plus_preview_burns_failed_sessions() {
        let vector = spake2plus_vector();
        let w0 = hex(&vector.w0);
        let w1 = hex(&vector.w1);
        let l = hex(&vector.l);
        let context = vector.context.into_bytes();
        let id_prover = vector.id_prover.into_bytes();
        let id_verifier = vector.id_verifier.into_bytes();

        let prover = CoreSpake2PlusProverSession::new(
            context.clone(),
            id_prover.clone(),
            id_verifier.clone(),
            w0.clone(),
            w1,
        )
        .unwrap();
        let verifier =
            CoreSpake2PlusVerifierSession::new(context, id_prover, id_verifier, w0, l).unwrap();
        let share_p = prover.start().unwrap();
        let response = verifier.respond(share_p).unwrap();

        let mut tampered = response.confirmation.clone();
        tampered[0] ^= 0x01;
        assert!(matches!(
            prover.finish(response.share_v.clone(), tampered),
            Err(CoreSpake2PlusError::ConfirmationMismatch)
        ));
        assert!(matches!(
            prover.finish(response.share_v, response.confirmation),
            Err(CoreSpake2PlusError::Invalid(_))
        ));
    }
}
