use std::fmt;

use flatbuffers::{FlatBufferBuilder, WIPOffset};

use crate::fb::{
    finish_envelope_buffer, ControlHeader, ControlHeaderArgs, ControlMessage, ControlMessageArgs,
    ControlType, Envelope, EnvelopeArgs, EventType, InputEvent, InputEventArgs, MessagePayload,
    SenderRole,
};

pub const FILE_IDENTIFIER: &str = "ADEN";
pub const VERSION: u32 = 1;
pub const MAX_ENVELOPE_BYTES: usize = 1024 * 1024;
pub const MAX_HEADER_STRING_BYTES: usize = 128;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AdfpError {
    Empty,
    Oversized,
    Truncated,
    WrongFileIdentifier,
    WrongVersion,
    HeaderMissing,
    HeaderInvalid(&'static str),
    HeaderExpired,
    UnsupportedPayload,
}

impl fmt::Display for AdfpError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{self:?}")
    }
}

impl std::error::Error for AdfpError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AdfpHeader {
    pub message_id: String,
    pub sender_device_id: String,
    pub sender_role: SenderRole,
    pub correlation_id: Option<String>,
    pub idempotency_key: Option<String>,
    pub expires_at_epoch_millis: u64,
    pub cancellation_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AdfpInputEvent {
    pub version: u32,
    pub event_type: EventType,
    pub session_id: String,
    pub generation: u32,
    pub seq: u32,
    pub timestamp: u64,
    pub x: f32,
    pub y: f32,
    pub dx: f32,
    pub dy: f32,
    pub button: u8,
    pub click_count: u8,
    pub key: Option<String>,
    pub code: Option<String>,
    pub modifiers: Vec<String>,
    pub text: Option<String>,
    pub width: f32,
    pub height: f32,
    pub target: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AdfpControlMessage {
    pub version: u32,
    pub message_type: ControlType,
    pub session_id: String,
    pub generation: u32,
    pub seq: u32,
    pub timestamp: u64,
    pub appearance: Option<String>,
    pub message: Option<String>,
    pub action: Option<String>,
    pub width: f32,
    pub height: f32,
    pub code: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum AdfpPayload {
    Input(AdfpInputEvent),
    Control(AdfpControlMessage),
}

#[derive(Debug, Clone, PartialEq)]
pub struct AdfpEnvelope {
    pub header: AdfpHeader,
    pub payload: AdfpPayload,
}

pub fn decode(data: &[u8], now_epoch_millis: u64) -> Result<AdfpEnvelope, AdfpError> {
    validate_envelope(data)?;
    let envelope = flatbuffers::root::<Envelope>(data).map_err(|_| AdfpError::Truncated)?;
    if envelope.version() != VERSION {
        return Err(AdfpError::WrongVersion);
    }
    let header = envelope.header().ok_or(AdfpError::HeaderMissing)?;
    let header = read_header(&header, now_epoch_millis)?;

    let payload = match envelope.payload_type() {
        MessagePayload::InputEvent => {
            let input = envelope
                .payload_as_input_event()
                .ok_or(AdfpError::UnsupportedPayload)?;
            AdfpPayload::Input(read_input(&input))
        }
        MessagePayload::ControlMessage => {
            let control = envelope
                .payload_as_control_message()
                .ok_or(AdfpError::UnsupportedPayload)?;
            AdfpPayload::Control(read_control(&control))
        }
        _ => return Err(AdfpError::UnsupportedPayload),
    };
    Ok(AdfpEnvelope { header, payload })
}

pub fn encode_input(
    event: &AdfpInputEvent,
    header: &AdfpHeader,
    now_epoch_millis: u64,
) -> Result<Vec<u8>, AdfpError> {
    validate_header(header, now_epoch_millis)?;
    if event.session_id.is_empty() {
        return Err(AdfpError::UnsupportedPayload);
    }

    let mut builder = FlatBufferBuilder::new();
    let session_id = builder.create_string(&event.session_id);
    let key = event.key.as_ref().map(|value| builder.create_string(value));
    let code = event
        .code
        .as_ref()
        .map(|value| builder.create_string(value));
    let text = event
        .text
        .as_ref()
        .map(|value| builder.create_string(value));
    let target = event
        .target
        .as_ref()
        .map(|value| builder.create_string(value));
    let modifier_offsets: Vec<WIPOffset<&str>> = event
        .modifiers
        .iter()
        .map(|modifier| builder.create_string(modifier))
        .collect();
    let modifiers = if modifier_offsets.is_empty() {
        None
    } else {
        Some(builder.create_vector(&modifier_offsets))
    };
    let input = InputEvent::create(
        &mut builder,
        &InputEventArgs {
            version: event.version,
            type_: event.event_type,
            session_id: Some(session_id),
            generation: event.generation,
            seq: event.seq,
            timestamp: event.timestamp,
            x: event.x,
            y: event.y,
            dx: event.dx,
            dy: event.dy,
            button: event.button,
            click_count: event.click_count,
            key,
            code,
            modifiers,
            text,
            width: event.width,
            height: event.height,
            target,
        },
    );
    let header = build_header(&mut builder, header);
    let envelope = Envelope::create(
        &mut builder,
        &EnvelopeArgs {
            version: VERSION,
            payload_type: MessagePayload::InputEvent,
            payload: Some(input.as_union_value()),
            header: Some(header),
            ..Default::default()
        },
    );
    finish(builder, envelope)
}

pub fn encode_control(
    message: &AdfpControlMessage,
    header: &AdfpHeader,
    now_epoch_millis: u64,
) -> Result<Vec<u8>, AdfpError> {
    validate_header(header, now_epoch_millis)?;
    if message.session_id.is_empty() {
        return Err(AdfpError::UnsupportedPayload);
    }

    let mut builder = FlatBufferBuilder::new();
    let session_id = builder.create_string(&message.session_id);
    let appearance = message
        .appearance
        .as_ref()
        .map(|value| builder.create_string(value));
    let text = message
        .message
        .as_ref()
        .map(|value| builder.create_string(value));
    let action = message
        .action
        .as_ref()
        .map(|value| builder.create_string(value));
    let code = message
        .code
        .as_ref()
        .map(|value| builder.create_string(value));
    let control = ControlMessage::create(
        &mut builder,
        &ControlMessageArgs {
            version: message.version,
            type_: message.message_type,
            session_id: Some(session_id),
            generation: message.generation,
            seq: message.seq,
            timestamp: message.timestamp,
            appearance,
            message: text,
            action,
            width: message.width,
            height: message.height,
            code,
        },
    );
    let header = build_header(&mut builder, header);
    let envelope = Envelope::create(
        &mut builder,
        &EnvelopeArgs {
            version: VERSION,
            payload_type: MessagePayload::ControlMessage,
            payload: Some(control.as_union_value()),
            header: Some(header),
            ..Default::default()
        },
    );
    finish(builder, envelope)
}

fn finish<'a>(
    mut builder: FlatBufferBuilder<'a>,
    envelope: WIPOffset<Envelope<'a>>,
) -> Result<Vec<u8>, AdfpError> {
    finish_envelope_buffer(&mut builder, envelope);
    let bytes = builder.finished_data().to_vec();
    if bytes.len() > MAX_ENVELOPE_BYTES {
        return Err(AdfpError::Oversized);
    }
    Ok(bytes)
}

fn build_header<'a>(
    builder: &mut FlatBufferBuilder<'a>,
    header: &AdfpHeader,
) -> WIPOffset<ControlHeader<'a>> {
    let message_id = builder.create_string(&header.message_id);
    let sender_device_id = builder.create_string(&header.sender_device_id);
    let correlation_id = header
        .correlation_id
        .as_ref()
        .map(|value| builder.create_string(value));
    let idempotency_key = header
        .idempotency_key
        .as_ref()
        .map(|value| builder.create_string(value));
    let cancellation_id = header
        .cancellation_id
        .as_ref()
        .map(|value| builder.create_string(value));
    ControlHeader::create(
        builder,
        &ControlHeaderArgs {
            message_id: Some(message_id),
            sender_device_id: Some(sender_device_id),
            sender_role: header.sender_role,
            correlation_id,
            idempotency_key,
            expires_at: header.expires_at_epoch_millis,
            cancellation_id,
        },
    )
}

fn read_header(header: &ControlHeader<'_>, now_epoch_millis: u64) -> Result<AdfpHeader, AdfpError> {
    let decoded = AdfpHeader {
        message_id: header.message_id().unwrap_or_default().to_string(),
        sender_device_id: header.sender_device_id().unwrap_or_default().to_string(),
        sender_role: header.sender_role(),
        correlation_id: header.correlation_id().map(str::to_string),
        idempotency_key: header.idempotency_key().map(str::to_string),
        expires_at_epoch_millis: header.expires_at(),
        cancellation_id: header.cancellation_id().map(str::to_string),
    };
    validate_header(&decoded, now_epoch_millis)?;
    Ok(decoded)
}

fn validate_header(header: &AdfpHeader, now_epoch_millis: u64) -> Result<(), AdfpError> {
    validate_header_string(Some(&header.message_id), "messageId", true)?;
    validate_header_string(Some(&header.sender_device_id), "senderDeviceId", true)?;
    validate_header_string(header.correlation_id.as_deref(), "correlationId", false)?;
    validate_header_string(header.idempotency_key.as_deref(), "idempotencyKey", false)?;
    validate_header_string(header.cancellation_id.as_deref(), "cancellationId", false)?;
    if header.sender_role == SenderRole::unspecified {
        return Err(AdfpError::HeaderInvalid("senderRole"));
    }
    if header.expires_at_epoch_millis != 0 && header.expires_at_epoch_millis <= now_epoch_millis {
        return Err(AdfpError::HeaderExpired);
    }
    Ok(())
}

fn validate_header_string(
    value: Option<&str>,
    field: &'static str,
    required: bool,
) -> Result<(), AdfpError> {
    if required && value.unwrap_or_default().is_empty() {
        return Err(AdfpError::HeaderInvalid(field));
    }
    if value.is_some_and(|value| value.len() > MAX_HEADER_STRING_BYTES) {
        return Err(AdfpError::HeaderInvalid(field));
    }
    Ok(())
}

fn read_input(input: &InputEvent<'_>) -> AdfpInputEvent {
    AdfpInputEvent {
        version: input.version(),
        event_type: input.type_(),
        session_id: input.session_id().to_string(),
        generation: input.generation(),
        seq: input.seq(),
        timestamp: input.timestamp(),
        x: input.x(),
        y: input.y(),
        dx: input.dx(),
        dy: input.dy(),
        button: input.button(),
        click_count: input.click_count(),
        key: input.key().map(str::to_string),
        code: input.code().map(str::to_string),
        modifiers: input
            .modifiers()
            .map(|modifiers| modifiers.iter().map(str::to_string).collect())
            .unwrap_or_default(),
        text: input.text().map(str::to_string),
        width: input.width(),
        height: input.height(),
        target: input.target().map(str::to_string),
    }
}

fn read_control(control: &ControlMessage<'_>) -> AdfpControlMessage {
    AdfpControlMessage {
        version: control.version(),
        message_type: control.type_(),
        session_id: control.session_id().to_string(),
        generation: control.generation(),
        seq: control.seq(),
        timestamp: control.timestamp(),
        appearance: control.appearance().map(str::to_string),
        message: control.message().map(str::to_string),
        action: control.action().map(str::to_string),
        width: control.width(),
        height: control.height(),
        code: control.code().map(str::to_string),
    }
}

fn validate_envelope(data: &[u8]) -> Result<(), AdfpError> {
    if data.is_empty() {
        return Err(AdfpError::Empty);
    }
    if data.len() > MAX_ENVELOPE_BYTES {
        return Err(AdfpError::Oversized);
    }
    if data.len() < 8 {
        return Err(AdfpError::Truncated);
    }
    if &data[4..8] != FILE_IDENTIFIER.as_bytes() {
        return Err(AdfpError::WrongFileIdentifier);
    }
    let root = read_u32(data, 0) as usize;
    if root < 8 || root + 4 > data.len() {
        return Err(AdfpError::Truncated);
    }
    let vtable_start = root
        .checked_sub(read_u32(data, root) as usize)
        .ok_or(AdfpError::Truncated)?;
    if vtable_start + 4 > data.len() {
        return Err(AdfpError::Truncated);
    }
    let vtable_size = read_u16(data, vtable_start) as usize;
    if vtable_size < 4 || vtable_start + vtable_size > data.len() {
        return Err(AdfpError::Truncated);
    }
    Ok(())
}

fn read_u16(data: &[u8], offset: usize) -> u16 {
    u16::from_le_bytes([data[offset], data[offset + 1]])
}

fn read_u32(data: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes([
        data[offset],
        data[offset + 1],
        data[offset + 2],
        data[offset + 3],
    ])
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = include_str!("../../../protocol/fixtures/adfp/envelope-v1.json");
    const NOW: u64 = 1_700_000_000_000;

    fn case_hex(name: &str) -> Vec<u8> {
        hex(extract_hex_after(&format!("\"name\": \"{name}\""), FIXTURE))
    }

    fn extract_hex_after<'a>(marker: &str, source: &'a str) -> &'a str {
        let start = source.find(marker).expect("fixture marker");
        let start = source[start..].find("\"hex\": \"").expect("hex field") + start + 8;
        let end = source[start..].find('"').expect("hex terminator") + start;
        &source[start..end]
    }

    fn hex(value: &str) -> Vec<u8> {
        (0..value.len())
            .step_by(2)
            .map(|index| u8::from_str_radix(&value[index..index + 2], 16).unwrap())
            .collect()
    }

    #[test]
    fn input_fixture_decodes_and_round_trips() {
        let bytes = case_hex("input-key-down");
        let decoded = decode(&bytes, NOW).unwrap();

        assert_eq!(decoded.header.message_id, "message-1");
        assert_eq!(decoded.header.sender_device_id, "device-controller-1");
        assert_eq!(decoded.header.sender_role, SenderRole::controller);
        assert_eq!(decoded.header.expires_at_epoch_millis, 4_102_444_800_000);

        let AdfpPayload::Input(event) = &decoded.payload else {
            panic!("expected input payload");
        };
        assert_eq!(event.event_type, EventType::key_down);
        assert_eq!(event.session_id, "session-1");
        assert_eq!(event.generation, 7);
        assert_eq!(event.seq, 42);
        assert_eq!(event.timestamp, 1_700_000_000_123);
        assert_eq!(event.key.as_deref(), Some("a"));
        assert_eq!(event.code.as_deref(), Some("KeyA"));
        assert_eq!(event.modifiers, vec!["Shift"]);
        assert_eq!(event.target.as_deref(), Some("window-1"));

        let encoded = encode_input(event, &decoded.header, NOW).unwrap();
        assert_eq!(decode(&encoded, NOW).unwrap(), decoded);
    }

    #[test]
    fn control_fixture_decodes_and_round_trips() {
        let bytes = case_hex("control-notice");
        let decoded = decode(&bytes, NOW).unwrap();

        let AdfpPayload::Control(control) = &decoded.payload else {
            panic!("expected control payload");
        };
        assert_eq!(control.message_type, ControlType::notice);
        assert_eq!(control.session_id, "session-1");
        assert_eq!(control.generation, 7);
        assert_eq!(control.seq, 43);
        assert_eq!(control.timestamp, 1_700_000_000_124);
        assert_eq!(control.message.as_deref(), Some("connected"));
        assert_eq!(control.action.as_deref(), Some("focus"));

        let encoded = encode_control(control, &decoded.header, NOW).unwrap();
        assert_eq!(decode(&encoded, NOW).unwrap(), decoded);
    }

    #[test]
    fn invalid_fixtures_are_rejected() {
        let wrong_identifier = case_hex("wrong-file-identifier");
        assert_eq!(
            decode(&wrong_identifier, NOW),
            Err(AdfpError::WrongFileIdentifier)
        );

        let truncated = case_hex("truncated");
        assert_eq!(decode(&truncated, NOW), Err(AdfpError::Truncated));

        let input = case_hex("input-key-down");
        assert_eq!(
            decode(&input, 4_102_444_800_000),
            Err(AdfpError::HeaderExpired)
        );
        assert_eq!(decode(&[], NOW), Err(AdfpError::Empty));
    }
}
