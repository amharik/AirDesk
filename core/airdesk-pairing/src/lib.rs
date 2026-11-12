//! AD-PAIR-1 transcript, SAS, HKDF key schedule, scrypt registration and
//! research-only SPAKE2+ over P-256.
//!
//! The browser, Swift and Kotlin implementations remain the behavioural
//! references. SPAKE2+ is not wired into product pairing until independent
//! cryptographic review.

use std::fmt;

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use hkdf::Hkdf;
use num_bigint::BigUint;
use scrypt::{scrypt, Params};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use unicode_normalization::UnicodeNormalization;

pub mod spake2plus;

pub const AD_PAIR_TRANSCRIPT_DOMAIN: &str = "AD-PAIR-1";
pub const AD_PAIR_SAS_DOMAIN: &str = "AD-PAIR-1-SAS";
pub const AD_PAIR_KEY_SCHEDULE_DOMAIN: &str = "AD-PAIR-1-KS";
pub const AD_PAIR_KEY_SCHEDULE_VERSION: u32 = 1;
pub const AD_PAIR_SESSION_KEY_BYTES: usize = 32;

const CERTIFICATE_HASH_BYTES: usize = 32;
const MIN_BINDING_BYTES: usize = 16;
const MIN_EVIDENCE_BYTES: usize = 16;
const MAX_EVIDENCE_BYTES: usize = 1024;
const MIN_SALT_BYTES: usize = 16;
const MAX_SALT_BYTES: usize = 64;
const SCRYPT_LOG_N: u8 = 15;
const SCRYPT_R: u32 = 8;
const SCRYPT_P: u32 = 1;
const SCRYPT_OUTPUT_BYTES: usize = 80;
const P256_ORDER_HEX: &str = "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PairingError {
    MissingBinding,
    UnsupportedBinding,
    InvalidBinding,
    ChannelBindingMismatch,
    InvalidPakeEvidence(&'static str),
    TranscriptHashLength,
    InvalidSharedSecret,
    InvalidPassword,
    InvalidSalt,
    InvalidRegistrationScalar,
    Scrypt,
    Hkdf,
    Json,
}

impl fmt::Display for PairingError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidPakeEvidence(name) => write!(formatter, "invalid PAKE evidence: {name}"),
            Self::InvalidBinding => write!(formatter, "invalid channel binding"),
            Self::ChannelBindingMismatch => write!(formatter, "channel binding mismatch"),
            other => write!(formatter, "{other:?}"),
        }
    }
}

impl std::error::Error for PairingError {}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PairingChannelBinding {
    pub kind: String,
    pub value: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PairingPayload {
    pub protocol: String,
    pub version: String,
    #[serde(rename = "type")]
    pub payload_type: String,
    pub device_id: String,
    pub public_key: String,
    pub nonce: String,
    pub reply_to: Option<String>,
    pub expires_at: u64,
    pub endpoint_hint: Option<String>,
    pub relay_hint: Option<String>,
    pub capabilities: Vec<String>,
    pub channel_binding: PairingChannelBinding,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PakeEvidence {
    pub initiator_share: String,
    pub responder_share: String,
    pub initiator_confirmation: String,
    pub responder_confirmation: String,
}

pub struct PairingTranscriptInput<'a> {
    pub offer: &'a PairingPayload,
    pub response: &'a PairingPayload,
    pub pake: &'a PakeEvidence,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AdPairSessionKeys {
    pub version: u32,
    pub initiator_to_responder: [u8; AD_PAIR_SESSION_KEY_BYTES],
    pub responder_to_initiator: [u8; AD_PAIR_SESSION_KEY_BYTES],
    pub transport: [u8; AD_PAIR_SESSION_KEY_BYTES],
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PasswordScalars {
    pub w0: [u8; 32],
    pub w1: [u8; 32],
}

#[derive(Serialize)]
struct CanonicalPayload {
    #[serde(rename = "type")]
    payload_type: String,
    #[serde(rename = "deviceId")]
    device_id: String,
    #[serde(rename = "publicKey")]
    public_key: String,
    nonce: String,
    #[serde(rename = "replyTo")]
    reply_to: Option<String>,
    #[serde(rename = "expiresAt")]
    expires_at: u64,
    #[serde(rename = "endpointHint")]
    endpoint_hint: Option<String>,
    #[serde(rename = "relayHint")]
    relay_hint: Option<String>,
    capabilities: Vec<String>,
    #[serde(rename = "channelBinding")]
    channel_binding: PairingChannelBinding,
}

#[derive(Serialize)]
struct CanonicalPakeEvidence {
    #[serde(rename = "initiatorShare")]
    initiator_share: String,
    #[serde(rename = "responderShare")]
    responder_share: String,
    #[serde(rename = "initiatorConfirmation")]
    initiator_confirmation: String,
    #[serde(rename = "responderConfirmation")]
    responder_confirmation: String,
}

#[derive(Serialize)]
struct CanonicalTranscript {
    domain: &'static str,
    protocol: String,
    version: String,
    #[serde(rename = "channelBinding")]
    channel_binding: PairingChannelBinding,
    offer: CanonicalPayload,
    response: CanonicalPayload,
    pake: CanonicalPakeEvidence,
}

#[derive(Serialize)]
struct SessionKeyInfo {
    domain: &'static str,
    version: u32,
    label: &'static str,
    #[serde(rename = "channelBinding")]
    channel_binding: PairingChannelBinding,
    #[serde(rename = "transcriptHash")]
    transcript_hash: String,
}

pub fn require_channel_binding(
    binding: &PairingChannelBinding,
) -> Result<PairingChannelBinding, PairingError> {
    if binding.kind.is_empty() || binding.kind == "none" {
        return Err(PairingError::MissingBinding);
    }
    match binding.kind.as_str() {
        "certificate-hash" => {
            if binding.value.len() != CERTIFICATE_HASH_BYTES * 2
                || !binding.value.bytes().all(|byte| byte.is_ascii_hexdigit())
            {
                return Err(PairingError::InvalidBinding);
            }
            Ok(PairingChannelBinding {
                kind: binding.kind.clone(),
                value: binding.value.to_ascii_lowercase(),
            })
        }
        "exporter" => {
            let bytes = URL_SAFE_NO_PAD
                .decode(binding.value.as_bytes())
                .map_err(|_| PairingError::InvalidBinding)?;
            if bytes.len() < MIN_BINDING_BYTES {
                return Err(PairingError::InvalidBinding);
            }
            Ok(binding.clone())
        }
        _ => Err(PairingError::UnsupportedBinding),
    }
}

fn evidence_value(value: &str, name: &'static str) -> Result<String, PairingError> {
    let bytes = URL_SAFE_NO_PAD
        .decode(value.as_bytes())
        .map_err(|_| PairingError::InvalidPakeEvidence(name))?;
    if !(MIN_EVIDENCE_BYTES..=MAX_EVIDENCE_BYTES).contains(&bytes.len()) {
        return Err(PairingError::InvalidPakeEvidence(name));
    }
    Ok(value.to_string())
}

pub fn normalized_pake_evidence(pake: &PakeEvidence) -> Result<PakeEvidence, PairingError> {
    Ok(PakeEvidence {
        initiator_share: evidence_value(&pake.initiator_share, "initiator share")?,
        responder_share: evidence_value(&pake.responder_share, "responder share")?,
        initiator_confirmation: evidence_value(
            &pake.initiator_confirmation,
            "initiator confirmation",
        )?,
        responder_confirmation: evidence_value(
            &pake.responder_confirmation,
            "responder confirmation",
        )?,
    })
}

fn canonical_payload(
    payload: &PairingPayload,
    channel_binding: PairingChannelBinding,
) -> CanonicalPayload {
    let mut capabilities = payload.capabilities.clone();
    capabilities.sort();
    CanonicalPayload {
        payload_type: payload.payload_type.clone(),
        device_id: payload.device_id.clone(),
        public_key: payload.public_key.clone(),
        nonce: payload.nonce.clone(),
        reply_to: payload.reply_to.clone(),
        expires_at: payload.expires_at,
        endpoint_hint: payload.endpoint_hint.clone(),
        relay_hint: payload.relay_hint.clone(),
        capabilities,
        channel_binding,
    }
}

pub fn canonical_pairing_transcript(
    input: &PairingTranscriptInput<'_>,
) -> Result<Vec<u8>, PairingError> {
    let offer_binding = require_channel_binding(&input.offer.channel_binding)?;
    let response_binding = require_channel_binding(&input.response.channel_binding)?;
    if offer_binding != response_binding {
        return Err(PairingError::ChannelBindingMismatch);
    }
    let pake = normalized_pake_evidence(input.pake)?;
    let transcript = CanonicalTranscript {
        domain: AD_PAIR_TRANSCRIPT_DOMAIN,
        protocol: input.offer.protocol.clone(),
        version: input.offer.version.clone(),
        channel_binding: offer_binding.clone(),
        offer: canonical_payload(input.offer, offer_binding),
        response: canonical_payload(input.response, response_binding),
        pake: CanonicalPakeEvidence {
            initiator_share: pake.initiator_share,
            responder_share: pake.responder_share,
            initiator_confirmation: pake.initiator_confirmation,
            responder_confirmation: pake.responder_confirmation,
        },
    };
    let json = serde_json::to_vec(&transcript).map_err(|_| PairingError::Json)?;
    let mut bytes = Vec::with_capacity(AD_PAIR_TRANSCRIPT_DOMAIN.len() + 1 + json.len());
    bytes.extend_from_slice(AD_PAIR_TRANSCRIPT_DOMAIN.as_bytes());
    bytes.push(b'\n');
    bytes.extend_from_slice(&json);
    Ok(bytes)
}

pub fn hash_transcript(transcript: &[u8]) -> [u8; 32] {
    Sha256::digest(transcript).into()
}

pub fn pairing_transcript_hash(
    input: &PairingTranscriptInput<'_>,
) -> Result<[u8; 32], PairingError> {
    Ok(hash_transcript(&canonical_pairing_transcript(input)?))
}

pub fn derive_short_authentication_string(transcript_hash: &[u8]) -> Result<String, PairingError> {
    if transcript_hash.len() != 32 {
        return Err(PairingError::TranscriptHashLength);
    }
    let mut digest = Sha256::new();
    digest.update(AD_PAIR_SAS_DOMAIN.as_bytes());
    digest.update(b"\n");
    digest.update(transcript_hash);
    let digest = digest.finalize();
    let value = u32::from_be_bytes([digest[0], digest[1], digest[2], digest[3]]) % 1_000_000;
    Ok(format!("{value:06}"))
}

fn to_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut value = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        value.push(HEX[(byte >> 4) as usize] as char);
        value.push(HEX[(byte & 0x0f) as usize] as char);
    }
    value
}

fn derive_key(
    shared_secret: &[u8],
    transcript_hash: &[u8],
    channel_binding: &PairingChannelBinding,
    label: &'static str,
) -> Result<[u8; AD_PAIR_SESSION_KEY_BYTES], PairingError> {
    let info = SessionKeyInfo {
        domain: AD_PAIR_KEY_SCHEDULE_DOMAIN,
        version: AD_PAIR_KEY_SCHEDULE_VERSION,
        label,
        channel_binding: channel_binding.clone(),
        transcript_hash: to_hex(transcript_hash),
    };
    let info = serde_json::to_vec(&info).map_err(|_| PairingError::Json)?;
    let hkdf = Hkdf::<Sha256>::new(Some(transcript_hash), shared_secret);
    let mut output = [0_u8; AD_PAIR_SESSION_KEY_BYTES];
    hkdf.expand(&info, &mut output)
        .map_err(|_| PairingError::Hkdf)?;
    Ok(output)
}

pub fn derive_session_keys(
    shared_secret: &[u8],
    transcript_hash: &[u8],
    channel_binding: &PairingChannelBinding,
) -> Result<AdPairSessionKeys, PairingError> {
    if !(MIN_EVIDENCE_BYTES..=MAX_EVIDENCE_BYTES).contains(&shared_secret.len()) {
        return Err(PairingError::InvalidSharedSecret);
    }
    if transcript_hash.len() != 32 {
        return Err(PairingError::TranscriptHashLength);
    }
    let channel_binding = require_channel_binding(channel_binding)?;
    Ok(AdPairSessionKeys {
        version: AD_PAIR_KEY_SCHEDULE_VERSION,
        initiator_to_responder: derive_key(
            shared_secret,
            transcript_hash,
            &channel_binding,
            "i2r",
        )?,
        responder_to_initiator: derive_key(
            shared_secret,
            transcript_hash,
            &channel_binding,
            "r2i",
        )?,
        transport: derive_key(
            shared_secret,
            transcript_hash,
            &channel_binding,
            "transport",
        )?,
    })
}

fn push_length_prefixed(output: &mut Vec<u8>, bytes: &[u8]) {
    output.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
    output.extend_from_slice(bytes);
}

pub fn canonical_password_material(
    password: &[u8],
    id_prover: &[u8],
    id_verifier: &[u8],
) -> Vec<u8> {
    let mut material =
        Vec::with_capacity(24 + password.len() + id_prover.len() + id_verifier.len());
    push_length_prefixed(&mut material, password);
    push_length_prefixed(&mut material, id_prover);
    push_length_prefixed(&mut material, id_verifier);
    material
}

fn wide_scalar(bytes: &[u8]) -> [u8; 32] {
    let order = BigUint::parse_bytes(P256_ORDER_HEX.as_bytes(), 16).expect("P-256 order");
    let value = BigUint::from_bytes_be(bytes) % order;
    let bytes = value.to_bytes_be();
    let mut scalar = [0_u8; 32];
    scalar[32 - bytes.len()..].copy_from_slice(&bytes);
    scalar
}

pub fn derive_password_scalars(
    password: &[u8],
    salt: &[u8],
    id_prover: &[u8],
    id_verifier: &[u8],
) -> Result<PasswordScalars, PairingError> {
    if password.is_empty() {
        return Err(PairingError::InvalidPassword);
    }
    if !(MIN_SALT_BYTES..=MAX_SALT_BYTES).contains(&salt.len()) {
        return Err(PairingError::InvalidSalt);
    }
    let material = canonical_password_material(password, id_prover, id_verifier);
    // `Params::new` caps its advisory key length at 64 bytes, but the low-level
    // `scrypt` function writes the caller's output slice. AD-PAIR-1 needs 80.
    let params =
        Params::new(SCRYPT_LOG_N, SCRYPT_R, SCRYPT_P, 64).map_err(|_| PairingError::Scrypt)?;
    let mut output = [0_u8; SCRYPT_OUTPUT_BYTES];
    scrypt(&material, salt, &params, &mut output).map_err(|_| PairingError::Scrypt)?;
    let (w0, w1) = output.split_at(SCRYPT_OUTPUT_BYTES / 2);
    let w0 = wide_scalar(w0);
    let w1 = wide_scalar(w1);
    if w1 == [0_u8; 32] {
        return Err(PairingError::InvalidRegistrationScalar);
    }
    Ok(PasswordScalars { w0, w1 })
}

pub fn derive_text_password_scalars(
    password: &str,
    salt: &[u8],
    id_prover: &[u8],
    id_verifier: &[u8],
) -> Result<PasswordScalars, PairingError> {
    if password.is_empty() {
        return Err(PairingError::InvalidPassword);
    }
    let normalized: String = password.nfkc().collect();
    derive_password_scalars(normalized.as_bytes(), salt, id_prover, id_verifier)
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = include_str!("../../../protocol/fixtures/ad-pair-1.json");

    #[derive(Deserialize)]
    struct Fixture {
        binding: PairingChannelBinding,
        offer: PairingPayload,
        response: PairingPayload,
        pake: PakeEvidence,
        #[serde(rename = "pakeSecret")]
        pake_secret: String,
        password: String,
        registration: Registration,
        expected: Expected,
    }

    #[derive(Deserialize)]
    struct Registration {
        salt: String,
        w0: String,
        w1: String,
    }

    #[derive(Deserialize)]
    struct Expected {
        transcript: String,
        #[serde(rename = "transcriptHash")]
        transcript_hash: String,
        #[serde(rename = "shortAuthenticationString")]
        short_authentication_string: String,
        #[serde(rename = "sessionKeys")]
        session_keys: ExpectedSessionKeys,
    }

    #[derive(Deserialize)]
    struct ExpectedSessionKeys {
        #[serde(rename = "initiatorToResponder")]
        initiator_to_responder: String,
        #[serde(rename = "responderToInitiator")]
        responder_to_initiator: String,
        transport: String,
    }

    fn hex(value: &str) -> Vec<u8> {
        (0..value.len())
            .step_by(2)
            .map(|index| u8::from_str_radix(&value[index..index + 2], 16).unwrap())
            .collect()
    }

    fn fixture() -> Fixture {
        serde_json::from_str(FIXTURE).unwrap()
    }

    #[test]
    fn transcript_hash_and_sas_match_shared_fixture() {
        let fixture = fixture();
        let transcript = canonical_pairing_transcript(&PairingTranscriptInput {
            offer: &fixture.offer,
            response: &fixture.response,
            pake: &fixture.pake,
        })
        .unwrap();
        assert_eq!(to_hex(&transcript), fixture.expected.transcript);

        let hash = hash_transcript(&transcript);
        assert_eq!(to_hex(&hash), fixture.expected.transcript_hash);
        assert_eq!(
            derive_short_authentication_string(&hash).unwrap(),
            fixture.expected.short_authentication_string
        );
    }

    #[test]
    fn hkdf_session_keys_match_shared_fixture() {
        let fixture = fixture();
        let hash = hex(&fixture.expected.transcript_hash);
        let shared_secret = URL_SAFE_NO_PAD.decode(fixture.pake_secret).unwrap();
        let keys = derive_session_keys(&shared_secret, &hash, &fixture.binding).unwrap();

        assert_eq!(keys.version, 1);
        assert_eq!(
            to_hex(&keys.initiator_to_responder),
            fixture.expected.session_keys.initiator_to_responder
        );
        assert_eq!(
            to_hex(&keys.responder_to_initiator),
            fixture.expected.session_keys.responder_to_initiator
        );
        assert_eq!(
            to_hex(&keys.transport),
            fixture.expected.session_keys.transport
        );
    }

    #[test]
    fn scrypt_registration_matches_browser_vector() {
        let fixture = fixture();
        let salt = hex(&fixture.registration.salt);
        let scalars = derive_text_password_scalars(
            &fixture.password,
            &salt,
            fixture.response.device_id.as_bytes(),
            fixture.offer.device_id.as_bytes(),
        )
        .unwrap();
        assert_eq!(to_hex(&scalars.w0), fixture.registration.w0);
        assert_eq!(to_hex(&scalars.w1), fixture.registration.w1);
    }

    #[test]
    fn rejects_binding_evidence_and_password_mismatches() {
        let fixture = fixture();
        let mut response = fixture.response.clone();
        response.channel_binding.value = "cd".repeat(32);
        assert_eq!(
            canonical_pairing_transcript(&PairingTranscriptInput {
                offer: &fixture.offer,
                response: &response,
                pake: &fixture.pake,
            }),
            Err(PairingError::ChannelBindingMismatch)
        );

        let mut pake = fixture.pake.clone();
        pake.initiator_share = "not-base64!".to_string();
        assert_eq!(
            canonical_pairing_transcript(&PairingTranscriptInput {
                offer: &fixture.offer,
                response: &fixture.response,
                pake: &pake,
            }),
            Err(PairingError::InvalidPakeEvidence("initiator share"))
        );

        assert_eq!(
            derive_text_password_scalars(
                "",
                &hex(&fixture.registration.salt),
                fixture.response.device_id.as_bytes(),
                fixture.offer.device_id.as_bytes(),
            ),
            Err(PairingError::InvalidPassword)
        );
    }
}
