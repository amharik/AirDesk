use std::fmt;

use crate::fb::EventType;

pub const HEADER_BYTES: usize = 32;
const POINTER_BYTES: usize = 44;
const SCROLL_BYTES: usize = 40;
const VERSION: u8 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PackedError {
    InvalidLength,
    InvalidMagic,
    UnsupportedVersion,
    UnsupportedFlags,
    UnsupportedEvent,
    InvalidCoordinates,
    InvalidButton,
    InvalidClickCount,
    InvalidDelta,
    InvalidTimestamp,
    InvalidSession,
}

impl fmt::Display for PackedError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{self:?}")
    }
}

impl std::error::Error for PackedError {}

#[derive(Debug, Clone, PartialEq)]
pub struct PackedFrame {
    pub kind: EventType,
    pub generation: u32,
    pub seq: u32,
    pub timestamp: u64,
    pub session_tag: u64,
    pub x: Option<f32>,
    pub y: Option<f32>,
    pub button: Option<u8>,
    pub click_count: Option<u8>,
    pub dx: Option<f32>,
    pub dy: Option<f32>,
}

impl PackedFrame {
    pub fn session_tag(session_id: &str) -> Result<u64, PackedError> {
        if session_id.is_empty() || session_id.len() > 64 {
            return Err(PackedError::InvalidSession);
        }
        let mut hash = 0xcbf2_9ce4_8422_2325_u64;
        for byte in session_id.bytes() {
            hash ^= u64::from(byte);
            hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
        }
        Ok(hash)
    }

    pub fn encode(&self) -> Result<Vec<u8>, PackedError> {
        let kind = self.kind.0;
        if kind > 5 {
            return Err(PackedError::UnsupportedEvent);
        }
        if self.timestamp == 0 {
            return Err(PackedError::InvalidTimestamp);
        }

        let length = match kind {
            0..=3 => POINTER_BYTES,
            5 => SCROLL_BYTES,
            _ => HEADER_BYTES,
        };
        let mut data = Vec::with_capacity(length);
        data.extend_from_slice(&[0x41, 0x44, VERSION, kind, 0, 0, 0, 0]);
        data.extend_from_slice(&self.generation.to_le_bytes());
        data.extend_from_slice(&self.seq.to_le_bytes());
        data.extend_from_slice(&self.timestamp.to_le_bytes());
        data.extend_from_slice(&self.session_tag.to_le_bytes());

        if kind <= 3 {
            let x = normalized(self.x)?;
            let y = normalized(self.y)?;
            let button = self.button.ok_or(PackedError::InvalidButton)?;
            if button > 4 {
                return Err(PackedError::InvalidButton);
            }
            let click_count = self.click_count.ok_or(PackedError::InvalidClickCount)?;
            if !(1..=3).contains(&click_count) {
                return Err(PackedError::InvalidClickCount);
            }
            data.extend_from_slice(&x.to_bits().to_le_bytes());
            data.extend_from_slice(&y.to_bits().to_le_bytes());
            data.push(button);
            data.push(click_count);
            data.extend_from_slice(&[0, 0]);
        } else if kind == 5 {
            let dx = self.dx.ok_or(PackedError::InvalidDelta)?;
            let dy = self.dy.ok_or(PackedError::InvalidDelta)?;
            if !dx.is_finite() || !dy.is_finite() || dx.abs() > 20_000.0 || dy.abs() > 20_000.0 {
                return Err(PackedError::InvalidDelta);
            }
            data.extend_from_slice(&dx.to_bits().to_le_bytes());
            data.extend_from_slice(&dy.to_bits().to_le_bytes());
        }

        Ok(data)
    }

    pub fn decode(data: &[u8]) -> Result<Self, PackedError> {
        if data.len() < HEADER_BYTES {
            return Err(PackedError::InvalidLength);
        }
        if data[0] != 0x41 || data[1] != 0x44 {
            return Err(PackedError::InvalidMagic);
        }
        if data[2] != VERSION {
            return Err(PackedError::UnsupportedVersion);
        }
        if data[4..8] != [0, 0, 0, 0] {
            return Err(PackedError::UnsupportedFlags);
        }
        if data[3] > 5 {
            return Err(PackedError::UnsupportedEvent);
        }

        let timestamp = read_u64(data, 16);
        if timestamp == 0 {
            return Err(PackedError::InvalidTimestamp);
        }

        let mut frame = Self {
            kind: EventType(data[3]),
            generation: read_u32(data, 8),
            seq: read_u32(data, 12),
            timestamp,
            session_tag: read_u64(data, 24),
            x: None,
            y: None,
            button: None,
            click_count: None,
            dx: None,
            dy: None,
        };

        match data[3] {
            0..=3 => {
                if data.len() != POINTER_BYTES {
                    return Err(PackedError::InvalidLength);
                }
                let x = f32::from_bits(read_u32(data, 32));
                let y = f32::from_bits(read_u32(data, 36));
                if !x.is_finite()
                    || !y.is_finite()
                    || !(0.0..=1.0).contains(&x)
                    || !(0.0..=1.0).contains(&y)
                {
                    return Err(PackedError::InvalidCoordinates);
                }
                if data[40] > 4 {
                    return Err(PackedError::InvalidButton);
                }
                if !(1..=3).contains(&data[41]) || read_u16(data, 42) != 0 {
                    return Err(PackedError::InvalidClickCount);
                }
                frame.x = Some(x);
                frame.y = Some(y);
                frame.button = Some(data[40]);
                frame.click_count = Some(data[41]);
            }
            5 => {
                if data.len() != SCROLL_BYTES {
                    return Err(PackedError::InvalidLength);
                }
                let dx = f32::from_bits(read_u32(data, 32));
                let dy = f32::from_bits(read_u32(data, 36));
                if !dx.is_finite() || !dy.is_finite() || dx.abs() > 20_000.0 || dy.abs() > 20_000.0
                {
                    return Err(PackedError::InvalidDelta);
                }
                frame.dx = Some(dx);
                frame.dy = Some(dy);
            }
            _ => {
                if data.len() != HEADER_BYTES {
                    return Err(PackedError::InvalidLength);
                }
            }
        }

        Ok(frame)
    }
}

fn normalized(value: Option<f32>) -> Result<f32, PackedError> {
    match value {
        Some(value) if value.is_finite() && (0.0..=1.0).contains(&value) => Ok(value),
        _ => Err(PackedError::InvalidCoordinates),
    }
}

fn read_u16(data: &[u8], offset: usize) -> u16 {
    u16::from_le_bytes([data[offset], data[offset + 1]])
}

fn read_u32(data: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(data[offset..offset + 4].try_into().unwrap())
}

fn read_u64(data: &[u8], offset: usize) -> u64 {
    u64::from_le_bytes(data[offset..offset + 8].try_into().unwrap())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fb::{
        ControlMessage, ControlMessageArgs, ControlType, Envelope, EnvelopeArgs, MessagePayload,
    };
    use flatbuffers::FlatBufferBuilder;

    const SESSION_TAG: u64 = 1_623_645_925_111_568_461;
    const POINTER_HEX: &str =
        "4144010000000000070000002a0000007b68e5cf8b0100004d1849cf5d5988160000803e0000403f00010000";
    const SCROLL_HEX: &str =
        "4144010500000000070000002b0000007b68e5cf8b0100004d1849cf5d598816000048c100005040";
    const CANCEL_HEX: &str = "4144010400000000070000002c0000007b68e5cf8b0100004d1849cf5d598816";

    fn hex(value: &str) -> Vec<u8> {
        (0..value.len())
            .step_by(2)
            .map(|index| u8::from_str_radix(&value[index..index + 2], 16).unwrap())
            .collect()
    }

    #[test]
    fn session_tag_matches_shared_fixture() {
        assert_eq!(PackedFrame::session_tag("session-1"), Ok(SESSION_TAG));
    }

    #[test]
    fn pointer_fixture_decodes() {
        let frame = PackedFrame::decode(&hex(POINTER_HEX)).unwrap();
        assert_eq!(frame.kind, EventType::pointer_move);
        assert_eq!(frame.generation, 7);
        assert_eq!(frame.seq, 42);
        assert_eq!(frame.timestamp, 1_700_000_000_123);
        assert_eq!(frame.session_tag, SESSION_TAG);
        assert_eq!(frame.x, Some(0.25));
        assert_eq!(frame.y, Some(0.75));
        assert_eq!(frame.button, Some(0));
        assert_eq!(frame.click_count, Some(1));
    }

    #[test]
    fn fixtures_round_trip_byte_for_byte() {
        for fixture in [POINTER_HEX, SCROLL_HEX, CANCEL_HEX] {
            let bytes = hex(fixture);
            assert_eq!(
                PackedFrame::decode(&bytes).unwrap().encode().unwrap(),
                bytes
            );
        }
    }

    #[test]
    fn scroll_and_cancel_fixtures() {
        let scroll = PackedFrame::decode(&hex(SCROLL_HEX)).unwrap();
        assert_eq!(scroll.kind, EventType::scroll);
        assert_eq!(scroll.dx, Some(-12.5));
        assert_eq!(scroll.dy, Some(3.25));

        let cancel = PackedFrame::decode(&hex(CANCEL_HEX)).unwrap();
        assert_eq!(cancel.kind, EventType::pointer_cancel);
        assert_eq!(cancel.x, None);
    }

    #[test]
    fn malformed_frames_are_rejected() {
        let mut bad_magic = hex(POINTER_HEX);
        bad_magic[0] = 0;
        assert_eq!(
            PackedFrame::decode(&bad_magic),
            Err(PackedError::InvalidMagic)
        );

        let mut bad_version = hex(POINTER_HEX);
        bad_version[2] = 2;
        assert_eq!(
            PackedFrame::decode(&bad_version),
            Err(PackedError::UnsupportedVersion)
        );

        assert_eq!(
            PackedFrame::decode(&[0x41, 0x44]),
            Err(PackedError::InvalidLength)
        );
        assert_eq!(
            PackedFrame::session_tag(&"x".repeat(65)),
            Err(PackedError::InvalidSession)
        );
    }

    #[test]
    fn flatbuffer_control_envelope() {
        let mut builder = FlatBufferBuilder::new();
        let session = builder.create_string("session-1");
        let appearance = builder.create_string("light");
        let control = ControlMessage::create(
            &mut builder,
            &ControlMessageArgs {
                type_: ControlType::appearance,
                session_id: Some(session),
                generation: 7,
                seq: 2,
                timestamp: 1_700_000_000_123,
                appearance: Some(appearance),
                ..Default::default()
            },
        );
        let envelope = Envelope::create(
            &mut builder,
            &EnvelopeArgs {
                payload_type: MessagePayload::ControlMessage,
                payload: Some(control.as_union_value()),
                ..Default::default()
            },
        );
        builder.finish(envelope, Some("ADEN"));
        let decoded = flatbuffers::root::<Envelope>(builder.finished_data()).unwrap();

        assert_eq!(decoded.version(), 1);
        assert_eq!(decoded.payload_type(), MessagePayload::ControlMessage);
        let message = decoded.payload_as_control_message().unwrap();
        assert_eq!(message.type_(), ControlType::appearance);
        assert_eq!(message.session_id(), "session-1");
        assert_eq!(message.generation(), 7);
        assert_eq!(message.seq(), 2);
        assert_eq!(message.appearance(), Some("light"));
    }
}
