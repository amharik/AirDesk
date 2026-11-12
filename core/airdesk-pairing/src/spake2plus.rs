//! SPAKE2+ over P-256 for AD-PAIR-1 research.
//!
//! The construction follows RFC 9383 with the suite
//! `SPAKE2+-P256-SHA256-HKDF-SHA256-HMAC-SHA256`. It is intentionally not wired
//! into the product pairing flow: the browser, Swift and Kotlin implementations
//! remain the behavioural references until the independent crypto review.

use std::fmt;
use std::sync::OnceLock;

use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use p256::{
    elliptic_curve::{
        group::Group,
        sec1::{FromEncodedPoint, ToEncodedPoint},
        Field, PrimeField,
    },
    AffinePoint, EncodedPoint, FieldBytes, ProjectivePoint, Scalar,
};
use rand_core::OsRng;
use sha2::{Digest, Sha256};
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

pub const SPAKE2PLUS_P256_SUITE: &str = "SPAKE2+-P256-SHA256-HKDF-SHA256-HMAC-SHA256";
pub const SPAKE2PLUS_P256_M_COMPRESSED_HEX: &str =
    "02886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f";
pub const SPAKE2PLUS_P256_N_COMPRESSED_HEX: &str =
    "03d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b49";

const POINT_BYTES: usize = 65;
const SCALAR_BYTES: usize = 32;
const CONFIRMATION_BYTES: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Spake2PlusError {
    InvalidLength(&'static str),
    InvalidPoint(&'static str),
    IdentityPoint(&'static str),
    InvalidScalar(&'static str),
    ConfirmationMismatch,
    InvalidState(&'static str),
    Hkdf,
}

impl fmt::Display for Spake2PlusError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidLength(name) => write!(formatter, "{name} has an invalid length"),
            Self::InvalidPoint(name) => write!(formatter, "{name} is not a valid P-256 point"),
            Self::IdentityPoint(name) => write!(formatter, "{name} is the identity point"),
            Self::InvalidScalar(name) => write!(formatter, "{name} is outside the scalar range"),
            Self::ConfirmationMismatch => write!(formatter, "confirmation mismatch"),
            Self::InvalidState(message) => write!(formatter, "invalid state: {message}"),
            Self::Hkdf => write!(formatter, "HKDF expansion failed"),
        }
    }
}

impl std::error::Error for Spake2PlusError {}

#[derive(Clone, PartialEq, Eq, Zeroize, ZeroizeOnDrop)]
pub struct Spake2PlusKeys {
    pub k_main: [u8; 32],
    pub k_confirm_p: [u8; 32],
    pub k_confirm_v: [u8; 32],
    pub k_shared: [u8; 32],
}

impl fmt::Debug for Spake2PlusKeys {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("Spake2PlusKeys { .. }")
    }
}

#[derive(Clone, PartialEq, Eq, Zeroize, ZeroizeOnDrop)]
pub struct ProverInit {
    pub x: [u8; 32],
    pub share_p: [u8; 65],
}

pub struct ProverFinishInput<'a> {
    pub w0: &'a [u8],
    pub w1: &'a [u8],
    pub x: &'a [u8],
    pub share_v: &'a [u8],
    pub context: &'a [u8],
    pub id_prover: &'a [u8],
    pub id_verifier: &'a [u8],
}

pub struct ProverFinishResult {
    pub share_p: [u8; 65],
    pub share_v: [u8; 65],
    pub z: [u8; 65],
    pub v: [u8; 65],
    pub transcript: Zeroizing<Vec<u8>>,
    pub keys: Spake2PlusKeys,
    pub confirmation: [u8; 32],
    pub expected_confirmation: [u8; 32],
}

pub struct VerifierFinishInput<'a> {
    pub w0: &'a [u8],
    pub l: &'a [u8],
    pub share_p: &'a [u8],
    pub context: &'a [u8],
    pub id_prover: &'a [u8],
    pub id_verifier: &'a [u8],
    pub y: Option<&'a [u8]>,
}

pub struct VerifierFinishResult {
    pub y: Zeroizing<[u8; 32]>,
    pub share_p: [u8; 65],
    pub share_v: [u8; 65],
    pub z: [u8; 65],
    pub v: [u8; 65],
    pub transcript: Zeroizing<Vec<u8>>,
    pub keys: Spake2PlusKeys,
    pub confirmation: [u8; 32],
    pub expected_confirmation: [u8; 32],
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub struct VerifierResponse {
    pub share_v: [u8; 65],
    pub confirmation: [u8; 32],
    pub expected_confirmation: [u8; 32],
}

struct Confirmations {
    confirm_p: [u8; 32],
    confirm_v: [u8; 32],
}

fn nibble(byte: u8) -> u8 {
    match byte {
        b'0'..=b'9' => byte - b'0',
        b'a'..=b'f' => byte - b'a' + 10,
        b'A'..=b'F' => byte - b'A' + 10,
        _ => panic!("invalid hex digit"),
    }
}

fn decode_hex<const N: usize>(value: &str) -> [u8; N] {
    let bytes = value.as_bytes();
    assert_eq!(bytes.len(), N * 2, "hex length mismatch");
    let mut output = [0_u8; N];
    for (index, byte) in output.iter_mut().enumerate() {
        *byte = (nibble(bytes[index * 2]) << 4) | nibble(bytes[index * 2 + 1]);
    }
    output
}

fn decode_point(value: &[u8], name: &'static str) -> Result<ProjectivePoint, Spake2PlusError> {
    if value == [0_u8] {
        return Err(Spake2PlusError::IdentityPoint(name));
    }
    if value.len() != POINT_BYTES || value[0] != 0x04 {
        return Err(Spake2PlusError::InvalidLength(name));
    }
    let encoded =
        EncodedPoint::from_bytes(value).map_err(|_| Spake2PlusError::InvalidLength(name))?;
    let affine = Option::<AffinePoint>::from(AffinePoint::from_encoded_point(&encoded))
        .ok_or(Spake2PlusError::InvalidPoint(name))?;
    let point = ProjectivePoint::from(affine);
    if bool::from(point.is_identity()) {
        return Err(Spake2PlusError::IdentityPoint(name));
    }
    // P-256 has cofactor 1, so every valid on-curve point is in the prime-order
    // subgroup. `AffinePoint::from_encoded_point` above performs the on-curve
    // and coordinate-range checks.
    Ok(point)
}

fn encode_point(
    point: &ProjectivePoint,
    name: &'static str,
) -> Result<[u8; POINT_BYTES], Spake2PlusError> {
    if bool::from(point.is_identity()) {
        return Err(Spake2PlusError::IdentityPoint(name));
    }
    let encoded = point.to_affine().to_encoded_point(false);
    let bytes = encoded.as_bytes();
    if bytes.len() != POINT_BYTES {
        return Err(Spake2PlusError::InvalidLength(name));
    }
    let mut output = [0_u8; POINT_BYTES];
    output.copy_from_slice(bytes);
    Ok(output)
}

fn scalar_from_bytes(
    value: &[u8],
    name: &'static str,
    allow_zero: bool,
) -> Result<Scalar, Spake2PlusError> {
    if value.len() != SCALAR_BYTES {
        return Err(Spake2PlusError::InvalidLength(name));
    }
    let mut repr = FieldBytes::default();
    repr.copy_from_slice(value);
    let scalar = Option::<Scalar>::from(Scalar::from_repr(repr))
        .ok_or(Spake2PlusError::InvalidScalar(name))?;
    if !allow_zero && bool::from(scalar.is_zero()) {
        return Err(Spake2PlusError::InvalidScalar(name));
    }
    Ok(scalar)
}

fn zeroizing_scalar(
    value: &[u8],
    name: &'static str,
    allow_zero: bool,
) -> Result<Zeroizing<Scalar>, Spake2PlusError> {
    Ok(Zeroizing::new(scalar_from_bytes(value, name, allow_zero)?))
}

fn ephemeral_scalar(
    value: Option<&[u8]>,
    name: &'static str,
) -> Result<Zeroizing<Scalar>, Spake2PlusError> {
    if let Some(value) = value {
        return zeroizing_scalar(value, name, false);
    }
    loop {
        let scalar = Scalar::random(&mut OsRng);
        if !bool::from(scalar.is_zero()) {
            return Ok(Zeroizing::new(scalar));
        }
    }
}

fn scalar_bytes(scalar: &Scalar) -> [u8; 32] {
    let mut output = [0_u8; 32];
    output.copy_from_slice(scalar.to_bytes().as_slice());
    output
}

fn m_point() -> ProjectivePoint {
    static M: OnceLock<ProjectivePoint> = OnceLock::new();
    *M.get_or_init(|| {
        let bytes = decode_hex::<33>(SPAKE2PLUS_P256_M_COMPRESSED_HEX);
        let encoded = EncodedPoint::from_bytes(bytes).expect("valid compressed M");
        ProjectivePoint::from(
            Option::<AffinePoint>::from(AffinePoint::from_encoded_point(&encoded))
                .expect("valid M point"),
        )
    })
}

fn n_point() -> ProjectivePoint {
    static N: OnceLock<ProjectivePoint> = OnceLock::new();
    *N.get_or_init(|| {
        let bytes = decode_hex::<33>(SPAKE2PLUS_P256_N_COMPRESSED_HEX);
        let encoded = EncodedPoint::from_bytes(bytes).expect("valid compressed N");
        ProjectivePoint::from(
            Option::<AffinePoint>::from(AffinePoint::from_encoded_point(&encoded))
                .expect("valid N point"),
        )
    })
}

fn push_length_prefixed(output: &mut Vec<u8>, bytes: &[u8]) {
    output.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
    output.extend_from_slice(bytes);
}

fn hmac_sha256(key: &[u8], message: &[u8]) -> Result<[u8; 32], Spake2PlusError> {
    let mut mac = <Hmac<Sha256> as Mac>::new_from_slice(key).map_err(|_| Spake2PlusError::Hkdf)?;
    mac.update(message);
    let bytes = mac.finalize().into_bytes();
    let mut output = [0_u8; 32];
    output.copy_from_slice(&bytes);
    Ok(output)
}

pub fn assert_confirmation(expected: &[u8], received: &[u8]) -> Result<(), Spake2PlusError> {
    if expected.len() != CONFIRMATION_BYTES || received.len() != CONFIRMATION_BYTES {
        return Err(Spake2PlusError::InvalidLength("confirmation"));
    }
    let mismatch = expected
        .iter()
        .zip(received)
        .fold(0_u8, |accumulator, (left, right)| {
            accumulator | (left ^ right)
        });
    if mismatch != 0 {
        return Err(Spake2PlusError::ConfirmationMismatch);
    }
    Ok(())
}

pub struct TranscriptInput<'a> {
    pub context: &'a [u8],
    pub id_prover: &'a [u8],
    pub id_verifier: &'a [u8],
    pub share_p: &'a [u8],
    pub share_v: &'a [u8],
    pub z: &'a [u8],
    pub v: &'a [u8],
    pub w0: &'a [u8],
}

pub fn compute_transcript(input: TranscriptInput<'_>) -> Result<Vec<u8>, Spake2PlusError> {
    scalar_from_bytes(input.w0, "w0", true)?;
    let share_p = encode_point(&decode_point(input.share_p, "shareP")?, "shareP")?;
    let share_v = encode_point(&decode_point(input.share_v, "shareV")?, "shareV")?;
    let z = encode_point(&decode_point(input.z, "Z")?, "Z")?;
    let v = encode_point(&decode_point(input.v, "V")?, "V")?;
    let m = encode_point(&m_point(), "M")?;
    let n = encode_point(&n_point(), "N")?;

    let mut transcript = Vec::with_capacity(
        8 * 10
            + 7 * POINT_BYTES
            + input.context.len()
            + input.id_prover.len()
            + input.id_verifier.len(),
    );
    push_length_prefixed(&mut transcript, input.context);
    push_length_prefixed(&mut transcript, input.id_prover);
    push_length_prefixed(&mut transcript, input.id_verifier);
    push_length_prefixed(&mut transcript, &m);
    push_length_prefixed(&mut transcript, &n);
    push_length_prefixed(&mut transcript, &share_p);
    push_length_prefixed(&mut transcript, &share_v);
    push_length_prefixed(&mut transcript, &z);
    push_length_prefixed(&mut transcript, &v);
    push_length_prefixed(&mut transcript, input.w0);
    Ok(transcript)
}

pub fn derive_keys(transcript: &[u8]) -> Result<Spake2PlusKeys, Spake2PlusError> {
    let k_main: [u8; 32] = Sha256::digest(transcript).into();
    let mut confirmation_keys = [0_u8; 64];
    Hkdf::<Sha256>::new(Some(&[]), &k_main)
        .expand(b"ConfirmationKeys", &mut confirmation_keys)
        .map_err(|_| Spake2PlusError::Hkdf)?;
    let mut k_shared = [0_u8; 32];
    Hkdf::<Sha256>::new(Some(&[]), &k_main)
        .expand(b"SharedKey", &mut k_shared)
        .map_err(|_| Spake2PlusError::Hkdf)?;

    let mut k_confirm_p = [0_u8; 32];
    let mut k_confirm_v = [0_u8; 32];
    k_confirm_p.copy_from_slice(&confirmation_keys[..32]);
    k_confirm_v.copy_from_slice(&confirmation_keys[32..]);
    confirmation_keys.zeroize();

    Ok(Spake2PlusKeys {
        k_main,
        k_confirm_p,
        k_confirm_v,
        k_shared,
    })
}

fn compute_confirmations(
    keys: &Spake2PlusKeys,
    share_p: &[u8; 65],
    share_v: &[u8; 65],
) -> Result<Confirmations, Spake2PlusError> {
    Ok(Confirmations {
        confirm_p: hmac_sha256(&keys.k_confirm_p, share_v)?,
        confirm_v: hmac_sha256(&keys.k_confirm_v, share_p)?,
    })
}

pub fn registration_record(w1: &[u8]) -> Result<[u8; POINT_BYTES], Spake2PlusError> {
    let w1 = zeroizing_scalar(w1, "w1", false)?;
    encode_point(&(ProjectivePoint::generator() * w1.as_ref()), "L")
}

pub fn prover_init(w0: &[u8], x: Option<&[u8]>) -> Result<ProverInit, Spake2PlusError> {
    let w0 = zeroizing_scalar(w0, "w0", true)?;
    let x = ephemeral_scalar(x, "x")?;
    let share_p = encode_point(
        &(ProjectivePoint::generator() * x.as_ref() + m_point() * w0.as_ref()),
        "shareP",
    )?;
    Ok(ProverInit {
        x: scalar_bytes(&x),
        share_p,
    })
}

pub fn prover_finish(input: ProverFinishInput<'_>) -> Result<ProverFinishResult, Spake2PlusError> {
    let w0 = zeroizing_scalar(input.w0, "w0", true)?;
    let w1 = zeroizing_scalar(input.w1, "w1", false)?;
    let x = zeroizing_scalar(input.x, "x", false)?;
    let share_v_point = decode_point(input.share_v, "shareV")?;
    let share_p_point = ProjectivePoint::generator() * x.as_ref() + m_point() * w0.as_ref();

    let unblinded_share_v = share_v_point - n_point() * w0.as_ref();
    if bool::from(unblinded_share_v.is_identity()) {
        return Err(Spake2PlusError::IdentityPoint("shareV"));
    }
    let z_point = unblinded_share_v * x.as_ref();
    let v_point = unblinded_share_v * w1.as_ref();
    let z = encode_point(&z_point, "Z")?;
    let v = encode_point(&v_point, "V")?;
    let share_p = encode_point(&share_p_point, "shareP")?;
    let share_v = encode_point(&share_v_point, "shareV")?;
    let transcript = compute_transcript(TranscriptInput {
        context: input.context,
        id_prover: input.id_prover,
        id_verifier: input.id_verifier,
        share_p: &share_p,
        share_v: &share_v,
        z: &z,
        v: &v,
        w0: input.w0,
    })?;
    let keys = derive_keys(&transcript)?;
    let confirmations = compute_confirmations(&keys, &share_p, &share_v)?;

    Ok(ProverFinishResult {
        share_p,
        share_v,
        z,
        v,
        transcript: Zeroizing::new(transcript),
        keys,
        confirmation: confirmations.confirm_p,
        expected_confirmation: confirmations.confirm_v,
    })
}

pub fn verifier_finish(
    input: VerifierFinishInput<'_>,
) -> Result<VerifierFinishResult, Spake2PlusError> {
    let w0 = zeroizing_scalar(input.w0, "w0", true)?;
    let y = ephemeral_scalar(input.y, "y")?;
    let l_point = decode_point(input.l, "L")?;
    let share_p_point = decode_point(input.share_p, "shareP")?;
    let share_v_point = ProjectivePoint::generator() * y.as_ref() + n_point() * w0.as_ref();

    let unblinded_share_p = share_p_point - m_point() * w0.as_ref();
    if bool::from(unblinded_share_p.is_identity()) {
        return Err(Spake2PlusError::IdentityPoint("shareP"));
    }
    let z_point = unblinded_share_p * y.as_ref();
    let v_point = l_point * y.as_ref();
    let z = encode_point(&z_point, "Z")?;
    let v = encode_point(&v_point, "V")?;
    let share_p = encode_point(&share_p_point, "shareP")?;
    let share_v = encode_point(&share_v_point, "shareV")?;
    let transcript = compute_transcript(TranscriptInput {
        context: input.context,
        id_prover: input.id_prover,
        id_verifier: input.id_verifier,
        share_p: &share_p,
        share_v: &share_v,
        z: &z,
        v: &v,
        w0: input.w0,
    })?;
    let keys = derive_keys(&transcript)?;
    let confirmations = compute_confirmations(&keys, &share_p, &share_v)?;

    Ok(VerifierFinishResult {
        y: Zeroizing::new(scalar_bytes(&y)),
        share_p,
        share_v,
        z,
        v,
        transcript: Zeroizing::new(transcript),
        keys,
        confirmation: confirmations.confirm_v,
        expected_confirmation: confirmations.confirm_p,
    })
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum SessionPhase {
    Initial,
    AwaitingShare,
    AwaitingConfirmation,
    Completed,
    Failed,
}

pub struct ProverSession {
    w0: Vec<u8>,
    w1: Vec<u8>,
    context: Vec<u8>,
    id_prover: Vec<u8>,
    id_verifier: Vec<u8>,
    init: Option<ProverInit>,
    phase: SessionPhase,
}

impl ProverSession {
    pub fn new(
        context: &[u8],
        id_prover: &[u8],
        id_verifier: &[u8],
        w0: &[u8],
        w1: &[u8],
    ) -> Result<Self, Spake2PlusError> {
        scalar_from_bytes(w0, "w0", true)?;
        scalar_from_bytes(w1, "w1", false)?;
        Ok(Self {
            w0: w0.to_vec(),
            w1: w1.to_vec(),
            context: context.to_vec(),
            id_prover: id_prover.to_vec(),
            id_verifier: id_verifier.to_vec(),
            init: None,
            phase: SessionPhase::Initial,
        })
    }

    pub fn start(&mut self) -> Result<[u8; 65], Spake2PlusError> {
        if self.phase != SessionPhase::Initial {
            return Err(Spake2PlusError::InvalidState(
                "prover exchange already started",
            ));
        }
        let init = prover_init(&self.w0, None)?;
        let share_p = init.share_p;
        self.init = Some(init);
        self.phase = SessionPhase::AwaitingShare;
        Ok(share_p)
    }

    pub fn finish(
        &mut self,
        share_v: &[u8],
        confirmation_v: &[u8],
    ) -> Result<ProverFinishResult, Spake2PlusError> {
        if self.phase != SessionPhase::AwaitingShare {
            return Err(Spake2PlusError::InvalidState(
                "prover is not awaiting a verifier share",
            ));
        }
        let init = self
            .init
            .as_ref()
            .ok_or(Spake2PlusError::InvalidState("missing prover init"))?;
        let result = match prover_finish(ProverFinishInput {
            w0: &self.w0,
            w1: &self.w1,
            x: &init.x,
            share_v,
            context: &self.context,
            id_prover: &self.id_prover,
            id_verifier: &self.id_verifier,
        }) {
            Ok(result) => result,
            Err(error) => {
                self.burn();
                return Err(error);
            }
        };
        if let Err(error) = assert_confirmation(&result.expected_confirmation, confirmation_v) {
            self.burn();
            return Err(error);
        }
        self.phase = SessionPhase::Completed;
        Ok(result)
    }

    fn burn(&mut self) {
        self.init = None;
        self.w0.zeroize();
        self.w1.zeroize();
        self.phase = SessionPhase::Failed;
    }
}

impl Drop for ProverSession {
    fn drop(&mut self) {
        self.w0.zeroize();
        self.w1.zeroize();
    }
}

pub struct VerifierSession {
    w0: Vec<u8>,
    l: Vec<u8>,
    context: Vec<u8>,
    id_prover: Vec<u8>,
    id_verifier: Vec<u8>,
    pending: Option<VerifierFinishResult>,
    phase: SessionPhase,
}

impl VerifierSession {
    pub fn new(
        context: &[u8],
        id_prover: &[u8],
        id_verifier: &[u8],
        w0: &[u8],
        l: &[u8],
    ) -> Result<Self, Spake2PlusError> {
        scalar_from_bytes(w0, "w0", true)?;
        decode_point(l, "L")?;
        Ok(Self {
            w0: w0.to_vec(),
            l: l.to_vec(),
            context: context.to_vec(),
            id_prover: id_prover.to_vec(),
            id_verifier: id_verifier.to_vec(),
            pending: None,
            phase: SessionPhase::Initial,
        })
    }

    pub fn respond(&mut self, share_p: &[u8]) -> Result<VerifierResponse, Spake2PlusError> {
        if self.phase != SessionPhase::Initial {
            return Err(Spake2PlusError::InvalidState(
                "verifier response already produced",
            ));
        }
        let result = verifier_finish(VerifierFinishInput {
            w0: &self.w0,
            l: &self.l,
            share_p,
            context: &self.context,
            id_prover: &self.id_prover,
            id_verifier: &self.id_verifier,
            y: None,
        })?;
        let response = VerifierResponse {
            share_v: result.share_v,
            confirmation: result.confirmation,
            expected_confirmation: result.expected_confirmation,
        };
        self.pending = Some(result);
        self.phase = SessionPhase::AwaitingConfirmation;
        Ok(response)
    }

    pub fn finish(
        &mut self,
        confirmation_p: &[u8],
    ) -> Result<VerifierFinishResult, Spake2PlusError> {
        if self.phase != SessionPhase::AwaitingConfirmation {
            return Err(Spake2PlusError::InvalidState(
                "verifier is not awaiting a prover confirmation",
            ));
        }
        let result = self
            .pending
            .take()
            .ok_or(Spake2PlusError::InvalidState("missing verifier result"))?;
        if let Err(error) = assert_confirmation(&result.expected_confirmation, confirmation_p) {
            self.burn();
            return Err(error);
        }
        self.phase = SessionPhase::Completed;
        Ok(result)
    }

    fn burn(&mut self) {
        self.pending = None;
        self.w0.zeroize();
        self.phase = SessionPhase::Failed;
    }
}

impl Drop for VerifierSession {
    fn drop(&mut self) {
        self.w0.zeroize();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    const FIXTURE: &str = include_str!("../../../protocol/fixtures/spake2plus-p256-rfc9383.json");

    #[derive(Deserialize)]
    struct Vector {
        context: String,
        #[serde(rename = "idProver")]
        id_prover: String,
        #[serde(rename = "idVerifier")]
        id_verifier: String,
        w0: String,
        w1: String,
        #[serde(rename = "L")]
        l: String,
        x: String,
        #[serde(rename = "shareP")]
        share_p: String,
        y: String,
        #[serde(rename = "shareV")]
        share_v: String,
        #[serde(rename = "Z")]
        z: String,
        #[serde(rename = "V")]
        v: String,
        #[serde(rename = "TT")]
        tt: String,
        #[serde(rename = "K_main")]
        k_main: String,
        #[serde(rename = "K_confirmP")]
        k_confirm_p: String,
        #[serde(rename = "K_confirmV")]
        k_confirm_v: String,
        #[serde(rename = "confirmP")]
        confirm_p: String,
        #[serde(rename = "confirmV")]
        confirm_v: String,
        #[serde(rename = "K_shared")]
        k_shared: String,
    }

    fn hex(value: &str) -> Vec<u8> {
        assert_eq!(value.len() % 2, 0);
        let bytes = value.as_bytes();
        (0..bytes.len())
            .step_by(2)
            .map(|index| (nibble(bytes[index]) << 4) | nibble(bytes[index + 1]))
            .collect()
    }

    fn vector() -> Vector {
        serde_json::from_str(FIXTURE).expect("valid SPAKE2+ fixture")
    }

    #[test]
    fn reproduces_rfc9383_vector() {
        let vector = vector();
        let w0 = hex(&vector.w0);
        let w1 = hex(&vector.w1);
        let l = hex(&vector.l);
        let x = hex(&vector.x);
        let y = hex(&vector.y);

        assert_eq!(
            registration_record(&w1).unwrap().as_slice(),
            hex(&vector.l).as_slice()
        );

        let init = prover_init(&w0, Some(&x)).unwrap();
        assert_eq!(init.share_p.as_slice(), hex(&vector.share_p).as_slice());

        let prover = prover_finish(ProverFinishInput {
            w0: &w0,
            w1: &w1,
            x: &x,
            share_v: &hex(&vector.share_v),
            context: vector.context.as_bytes(),
            id_prover: vector.id_prover.as_bytes(),
            id_verifier: vector.id_verifier.as_bytes(),
        })
        .unwrap();
        let verifier = verifier_finish(VerifierFinishInput {
            w0: &w0,
            l: &l,
            share_p: &hex(&vector.share_p),
            context: vector.context.as_bytes(),
            id_prover: vector.id_prover.as_bytes(),
            id_verifier: vector.id_verifier.as_bytes(),
            y: Some(&y),
        })
        .unwrap();

        assert_eq!(prover.share_p.as_slice(), hex(&vector.share_p).as_slice());
        assert_eq!(prover.share_v.as_slice(), hex(&vector.share_v).as_slice());
        assert_eq!(prover.z.as_slice(), hex(&vector.z).as_slice());
        assert_eq!(prover.v.as_slice(), hex(&vector.v).as_slice());
        assert_eq!(prover.transcript.as_slice(), hex(&vector.tt).as_slice());
        assert_eq!(
            prover.keys.k_main.as_slice(),
            hex(&vector.k_main).as_slice()
        );
        assert_eq!(
            prover.keys.k_confirm_p.as_slice(),
            hex(&vector.k_confirm_p).as_slice()
        );
        assert_eq!(
            prover.keys.k_confirm_v.as_slice(),
            hex(&vector.k_confirm_v).as_slice()
        );
        assert_eq!(
            prover.keys.k_shared.as_slice(),
            hex(&vector.k_shared).as_slice()
        );
        assert_eq!(
            prover.confirmation.as_slice(),
            hex(&vector.confirm_p).as_slice()
        );
        assert_eq!(
            prover.expected_confirmation.as_slice(),
            hex(&vector.confirm_v).as_slice()
        );

        assert_eq!(verifier.share_p, prover.share_p);
        assert_eq!(verifier.share_v, prover.share_v);
        assert_eq!(verifier.z, prover.z);
        assert_eq!(verifier.v, prover.v);
        assert_eq!(verifier.transcript.as_slice(), prover.transcript.as_slice());
        assert_eq!(verifier.keys, prover.keys);
        assert_eq!(verifier.confirmation, prover.expected_confirmation);
        assert_eq!(verifier.expected_confirmation, prover.confirmation);

        assert_confirmation(&prover.expected_confirmation, &verifier.confirmation).unwrap();
        assert_confirmation(&verifier.expected_confirmation, &prover.confirmation).unwrap();
    }

    #[test]
    fn session_round_trip_verifies_confirm_v_before_confirm_p() {
        let vector = vector();
        let w0 = hex(&vector.w0);
        let w1 = hex(&vector.w1);
        let l = hex(&vector.l);
        let context = vector.context.as_bytes();
        let id_prover = vector.id_prover.as_bytes();
        let id_verifier = vector.id_verifier.as_bytes();

        let mut prover = ProverSession::new(context, id_prover, id_verifier, &w0, &w1).unwrap();
        let mut verifier = VerifierSession::new(context, id_prover, id_verifier, &w0, &l).unwrap();

        let share_p = prover.start().unwrap();
        let response = verifier.respond(&share_p).unwrap();

        let prover_result = prover
            .finish(&response.share_v, &response.confirmation)
            .unwrap();
        let verifier_result = verifier.finish(&prover_result.confirmation).unwrap();

        assert_eq!(prover_result.keys, verifier_result.keys);
        assert_eq!(
            prover_result.transcript.as_slice(),
            verifier_result.transcript.as_slice()
        );
    }

    #[test]
    fn confirmation_mismatch_burns_sessions() {
        let vector = vector();
        let w0 = hex(&vector.w0);
        let w1 = hex(&vector.w1);
        let l = hex(&vector.l);
        let context = vector.context.as_bytes();
        let id_prover = vector.id_prover.as_bytes();
        let id_verifier = vector.id_verifier.as_bytes();

        let mut prover = ProverSession::new(context, id_prover, id_verifier, &w0, &w1).unwrap();
        let mut verifier = VerifierSession::new(context, id_prover, id_verifier, &w0, &l).unwrap();
        let share_p = prover.start().unwrap();
        let response = verifier.respond(&share_p).unwrap();

        let mut tampered = response.confirmation;
        tampered[0] ^= 0x01;
        assert!(matches!(
            prover.finish(&response.share_v, &tampered),
            Err(Spake2PlusError::ConfirmationMismatch)
        ));
        assert!(matches!(
            prover.finish(&response.share_v, &response.confirmation),
            Err(Spake2PlusError::InvalidState(_))
        ));

        let mut prover = ProverSession::new(context, id_prover, id_verifier, &w0, &w1).unwrap();
        let mut verifier = VerifierSession::new(context, id_prover, id_verifier, &w0, &l).unwrap();
        let share_p = prover.start().unwrap();
        let response = verifier.respond(&share_p).unwrap();
        let prover_result = prover
            .finish(&response.share_v, &response.confirmation)
            .unwrap();

        let mut tampered = prover_result.confirmation;
        tampered[0] ^= 0x01;
        assert!(matches!(
            verifier.finish(&tampered),
            Err(Spake2PlusError::ConfirmationMismatch)
        ));
        assert!(matches!(
            verifier.finish(&prover_result.confirmation),
            Err(Spake2PlusError::InvalidState(_))
        ));
    }

    #[test]
    fn sessions_reject_out_of_order_operations() {
        let vector = vector();
        let w0 = hex(&vector.w0);
        let w1 = hex(&vector.w1);
        let l = hex(&vector.l);
        let context = vector.context.as_bytes();
        let id_prover = vector.id_prover.as_bytes();
        let id_verifier = vector.id_verifier.as_bytes();

        let mut prover = ProverSession::new(context, id_prover, id_verifier, &w0, &w1).unwrap();
        let mut verifier = VerifierSession::new(context, id_prover, id_verifier, &w0, &l).unwrap();

        assert!(matches!(
            prover.finish(&[0_u8; 65], &[0_u8; 32]),
            Err(Spake2PlusError::InvalidState(_))
        ));

        let share_p = prover.start().unwrap();
        assert!(matches!(
            prover.start(),
            Err(Spake2PlusError::InvalidState(_))
        ));

        let response = verifier.respond(&share_p).unwrap();
        assert!(matches!(
            verifier.respond(&share_p),
            Err(Spake2PlusError::InvalidState(_))
        ));

        let prover_result = prover
            .finish(&response.share_v, &response.confirmation)
            .unwrap();
        let verifier_result = verifier.finish(&prover_result.confirmation).unwrap();
        assert!(matches!(
            verifier.finish(&prover_result.confirmation),
            Err(Spake2PlusError::InvalidState(_))
        ));
        assert_eq!(prover_result.keys, verifier_result.keys);
    }

    #[test]
    fn rejects_identity_off_curve_lengths_and_bad_scalars() {
        let vector = vector();
        let w0 = hex(&vector.w0);
        let share_p = hex(&vector.share_p);
        let share_v = hex(&vector.share_v);
        let z = hex(&vector.z);
        let v = hex(&vector.v);

        let identity = [0_u8];
        assert_eq!(
            compute_transcript(TranscriptInput {
                context: vector.context.as_bytes(),
                id_prover: vector.id_prover.as_bytes(),
                id_verifier: vector.id_verifier.as_bytes(),
                share_p: &identity,
                share_v: &share_v,
                z: &z,
                v: &v,
                w0: &w0,
            })
            .unwrap_err(),
            Spake2PlusError::IdentityPoint("shareP")
        );

        let mut off_curve = [0_u8; 65];
        off_curve[0] = 0x04;
        assert!(matches!(
            compute_transcript(TranscriptInput {
                context: vector.context.as_bytes(),
                id_prover: vector.id_prover.as_bytes(),
                id_verifier: vector.id_verifier.as_bytes(),
                share_p: &off_curve,
                share_v: &share_v,
                z: &z,
                v: &v,
                w0: &w0,
            }),
            Err(Spake2PlusError::InvalidPoint("shareP"))
        ));

        assert!(matches!(
            prover_init(&[0_u8; 31], None),
            Err(Spake2PlusError::InvalidLength("w0"))
        ));
        assert!(matches!(
            prover_init(&w0, Some(&[0_u8; 32])),
            Err(Spake2PlusError::InvalidScalar("x"))
        ));
        assert!(matches!(
            registration_record(&[0_u8; 32]),
            Err(Spake2PlusError::InvalidScalar("w1"))
        ));
        assert!(matches!(
            verifier_finish(VerifierFinishInput {
                w0: &w0,
                l: &hex(&vector.l),
                share_p: &share_p,
                context: vector.context.as_bytes(),
                id_prover: vector.id_prover.as_bytes(),
                id_verifier: vector.id_verifier.as_bytes(),
                y: Some(&[0xff_u8; 32]),
            }),
            Err(Spake2PlusError::InvalidScalar("y"))
        ));
    }

    #[test]
    fn confirmation_validation_is_length_checked_and_constant_time() {
        let vector = vector();
        let confirmation = hex(&vector.confirm_p);
        assert_eq!(
            assert_confirmation(&confirmation, &[0_u8; 31]),
            Err(Spake2PlusError::InvalidLength("confirmation"))
        );

        let mut tampered = [0_u8; 32];
        tampered.copy_from_slice(&confirmation);
        tampered[31] ^= 0x80;
        assert_eq!(
            assert_confirmation(&confirmation, &tampered),
            Err(Spake2PlusError::ConfirmationMismatch)
        );
        assert_confirmation(&confirmation, &confirmation).unwrap();
    }

    #[test]
    fn keys_support_explicit_zeroization() {
        let vector = vector();
        let mut keys = derive_keys(&hex(&vector.tt)).unwrap();
        keys.zeroize();
        assert_eq!(keys.k_main, [0_u8; 32]);
        assert_eq!(keys.k_confirm_p, [0_u8; 32]);
        assert_eq!(keys.k_confirm_v, [0_u8; 32]);
        assert_eq!(keys.k_shared, [0_u8; 32]);
    }
}
