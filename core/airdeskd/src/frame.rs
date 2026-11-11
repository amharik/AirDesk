use std::fmt;
use std::io::{self, Read, Write};

use airdesk_protocol::fb::{
    finish_envelope_buffer, CapabilityLease, CapabilityLeaseArgs, Envelope, EnvelopeArgs,
    FabricPayload, MessagePayload, TerminalMessage, TerminalMessageArgs, TerminalMessageType,
};
use flatbuffers::FlatBufferBuilder;

pub const MAX_FRAME_BYTES: usize = 1024 * 1024;
pub const TERMINAL_VERSION: u32 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerminalFrameType {
    Attach,
    Attached,
    Data,
    Resize,
    Detach,
    Exit,
    Error,
}

impl TerminalFrameType {
    fn from_wire(value: TerminalMessageType) -> Option<Self> {
        match value {
            TerminalMessageType::attach => Some(Self::Attach),
            TerminalMessageType::attached => Some(Self::Attached),
            TerminalMessageType::data => Some(Self::Data),
            TerminalMessageType::resize => Some(Self::Resize),
            TerminalMessageType::detach => Some(Self::Detach),
            TerminalMessageType::exit => Some(Self::Exit),
            TerminalMessageType::error => Some(Self::Error),
            _ => None,
        }
    }

    fn to_wire(self) -> TerminalMessageType {
        match self {
            Self::Attach => TerminalMessageType::attach,
            Self::Attached => TerminalMessageType::attached,
            Self::Data => TerminalMessageType::data,
            Self::Resize => TerminalMessageType::resize,
            Self::Detach => TerminalMessageType::detach,
            Self::Exit => TerminalMessageType::exit,
            Self::Error => TerminalMessageType::error,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TerminalFrame {
    pub frame_type: TerminalFrameType,
    pub session_id: String,
    pub client_id: Option<String>,
    pub lease_id: Option<String>,
    pub sequence: u64,
    pub replay_from_sequence: u64,
    pub oldest_sequence: u64,
    pub data: Vec<u8>,
    pub columns: u32,
    pub rows: u32,
    pub exit_code: i32,
    pub message: Option<String>,
    pub truncated: bool,
}

impl TerminalFrame {
    pub fn attach(
        session_id: impl Into<String>,
        client_id: impl Into<String>,
        lease_id: impl Into<String>,
        replay_from_sequence: u64,
    ) -> Self {
        Self {
            frame_type: TerminalFrameType::Attach,
            session_id: session_id.into(),
            client_id: Some(client_id.into()),
            lease_id: Some(lease_id.into()),
            replay_from_sequence,
            ..Self::default()
        }
    }

    pub fn attached(
        session_id: impl Into<String>,
        client_id: impl Into<String>,
        oldest_sequence: u64,
        next_sequence: u64,
        truncated: bool,
    ) -> Self {
        Self {
            frame_type: TerminalFrameType::Attached,
            session_id: session_id.into(),
            client_id: Some(client_id.into()),
            sequence: next_sequence,
            oldest_sequence,
            truncated,
            ..Self::default()
        }
    }

    pub fn data(
        session_id: impl Into<String>,
        client_id: impl Into<String>,
        sequence: u64,
        data: Vec<u8>,
    ) -> Self {
        Self {
            frame_type: TerminalFrameType::Data,
            session_id: session_id.into(),
            client_id: Some(client_id.into()),
            sequence,
            data,
            ..Self::default()
        }
    }

    pub fn request(
        frame_type: TerminalFrameType,
        session_id: impl Into<String>,
        client_id: impl Into<String>,
        lease_id: impl Into<String>,
    ) -> Self {
        Self {
            frame_type,
            session_id: session_id.into(),
            client_id: Some(client_id.into()),
            lease_id: Some(lease_id.into()),
            ..Self::default()
        }
    }

    pub fn error(
        session_id: impl Into<String>,
        client_id: Option<String>,
        message: impl Into<String>,
    ) -> Self {
        Self {
            frame_type: TerminalFrameType::Error,
            session_id: session_id.into(),
            client_id,
            message: Some(message.into()),
            ..Self::default()
        }
    }

    pub fn encode(&self) -> Result<Vec<u8>, FrameError> {
        if self.session_id.is_empty() {
            return Err(FrameError::Invalid("session id"));
        }
        let mut builder = FlatBufferBuilder::new();
        let session_id = builder.create_string(&self.session_id);
        let client_id = self
            .client_id
            .as_ref()
            .map(|value| builder.create_string(value));
        let lease_id = self
            .lease_id
            .as_ref()
            .map(|value| builder.create_string(value));
        let lease = lease_id.map(|lease_id| {
            CapabilityLease::create(
                &mut builder,
                &CapabilityLeaseArgs {
                    lease_id: Some(lease_id),
                    session_id: Some(session_id),
                    ..Default::default()
                },
            )
        });
        let data = if self.data.is_empty() {
            None
        } else {
            Some(builder.create_vector(&self.data))
        };
        let message = self
            .message
            .as_ref()
            .map(|value| builder.create_string(value));
        let terminal = TerminalMessage::create(
            &mut builder,
            &TerminalMessageArgs {
                version: TERMINAL_VERSION,
                type_: self.frame_type.to_wire(),
                session_id: Some(session_id),
                client_id,
                lease,
                sequence: self.sequence,
                replay_from_sequence: self.replay_from_sequence,
                oldest_sequence: self.oldest_sequence,
                data,
                columns: self.columns,
                rows: self.rows,
                exit_code: self.exit_code,
                message,
                truncated: self.truncated,
            },
        );
        let envelope = Envelope::create(
            &mut builder,
            &EnvelopeArgs {
                version: 1,
                payload_type: MessagePayload::NONE,
                payload: None,
                header: None,
                fabric_payload_type: FabricPayload::TerminalMessage,
                fabric_payload: Some(terminal.as_union_value()),
            },
        );
        finish_envelope_buffer(&mut builder, envelope);
        let bytes = builder.finished_data().to_vec();
        if bytes.len() > MAX_FRAME_BYTES {
            return Err(FrameError::TooLarge);
        }
        Ok(bytes)
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, FrameError> {
        if bytes.is_empty() {
            return Err(FrameError::Empty);
        }
        if bytes.len() > MAX_FRAME_BYTES {
            return Err(FrameError::TooLarge);
        }
        let envelope = flatbuffers::root::<Envelope>(bytes).map_err(|_| FrameError::Malformed)?;
        if envelope.version() != 1 {
            return Err(FrameError::UnsupportedVersion(envelope.version()));
        }
        if envelope.fabric_payload_type() != FabricPayload::TerminalMessage {
            return Err(FrameError::WrongPayload);
        }
        let terminal = envelope
            .fabric_payload_as_terminal_message()
            .ok_or(FrameError::WrongPayload)?;
        if terminal.version() != TERMINAL_VERSION {
            return Err(FrameError::UnsupportedVersion(terminal.version()));
        }
        let frame_type = TerminalFrameType::from_wire(terminal.type_())
            .ok_or(FrameError::UnsupportedType(terminal.type_().0))?;
        let session_id = terminal.session_id().to_string();
        if session_id.is_empty() {
            return Err(FrameError::Invalid("session id"));
        }
        let data = terminal
            .data()
            .map(|value| value.bytes().to_vec())
            .unwrap_or_default();
        Ok(Self {
            frame_type,
            session_id,
            client_id: terminal.client_id().map(str::to_string),
            lease_id: terminal
                .lease()
                .and_then(|lease| lease.lease_id().map(str::to_string)),
            sequence: terminal.sequence(),
            replay_from_sequence: terminal.replay_from_sequence(),
            oldest_sequence: terminal.oldest_sequence(),
            data,
            columns: terminal.columns(),
            rows: terminal.rows(),
            exit_code: terminal.exit_code(),
            message: terminal.message().map(str::to_string),
            truncated: terminal.truncated(),
        })
    }

    pub fn write_to(&self, writer: &mut impl Write) -> Result<(), FrameError> {
        let bytes = self.encode()?;
        let length = u32::try_from(bytes.len()).map_err(|_| FrameError::TooLarge)?;
        writer
            .write_all(&length.to_be_bytes())
            .map_err(FrameError::Io)?;
        writer.write_all(&bytes).map_err(FrameError::Io)?;
        writer.flush().map_err(FrameError::Io)
    }

    pub fn read_from(reader: &mut impl Read) -> Result<Self, FrameError> {
        let mut length = [0u8; 4];
        reader.read_exact(&mut length).map_err(|error| {
            if error.kind() == io::ErrorKind::UnexpectedEof {
                FrameError::Closed
            } else {
                FrameError::Io(error)
            }
        })?;
        let length = u32::from_be_bytes(length) as usize;
        if length == 0 {
            return Err(FrameError::Empty);
        }
        if length > MAX_FRAME_BYTES {
            return Err(FrameError::TooLarge);
        }
        let mut bytes = vec![0u8; length];
        reader.read_exact(&mut bytes).map_err(FrameError::Io)?;
        Self::decode(&bytes)
    }
}

impl Default for TerminalFrame {
    fn default() -> Self {
        Self {
            frame_type: TerminalFrameType::Attach,
            session_id: String::new(),
            client_id: None,
            lease_id: None,
            sequence: 0,
            replay_from_sequence: 0,
            oldest_sequence: 0,
            data: Vec::new(),
            columns: 80,
            rows: 24,
            exit_code: 0,
            message: None,
            truncated: false,
        }
    }
}

#[derive(Debug)]
pub enum FrameError {
    Empty,
    TooLarge,
    Malformed,
    WrongPayload,
    UnsupportedVersion(u32),
    UnsupportedType(u32),
    Invalid(&'static str),
    Closed,
    Io(io::Error),
}

impl fmt::Display for FrameError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Empty => write!(formatter, "empty frame"),
            Self::TooLarge => write!(formatter, "frame exceeds the size limit"),
            Self::Malformed => write!(formatter, "malformed ADFP envelope"),
            Self::WrongPayload => write!(formatter, "frame is not a terminal payload"),
            Self::UnsupportedVersion(version) => write!(formatter, "unsupported version {version}"),
            Self::UnsupportedType(value) => {
                write!(formatter, "unsupported terminal message type {value}")
            }
            Self::Invalid(field) => write!(formatter, "invalid {field}"),
            Self::Closed => write!(formatter, "stream closed"),
            Self::Io(error) => write!(formatter, "{error}"),
        }
    }
}

impl std::error::Error for FrameError {}

impl From<io::Error> for FrameError {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}
