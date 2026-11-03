use std::fmt;

pub const MAGIC: u8 = 0xa5;
pub const BYTES: usize = 16;

pub const MODIFIER_SHIFT: u8 = 1 << 0;
pub const MODIFIER_OPTION: u8 = 1 << 1;
pub const MODIFIER_COMMAND: u8 = 1 << 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PackedMovementError {
    InvalidLength,
    InvalidMagic,
    EdgeNotAllowed,
    InvalidCoordinates,
    InvalidButtonMask,
    InvalidModifiers,
}

impl fmt::Display for PackedMovementError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{self:?}")
    }
}

impl std::error::Error for PackedMovementError {}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PackedMovementFrame {
    pub lease_epoch_low: u16,
    pub seq: u32,
    pub x: f32,
    pub y: f32,
    pub button_mask: u8,
    pub modifiers: u8,
}

impl PackedMovementFrame {
    pub fn encode(&self) -> Result<[u8; BYTES], PackedMovementError> {
        if !self.x.is_finite()
            || !self.y.is_finite()
            || !(0.0..=1.0).contains(&self.x)
            || !(0.0..=1.0).contains(&self.y)
        {
            return Err(PackedMovementError::InvalidCoordinates);
        }
        if self.button_mask > 0b111 {
            return Err(PackedMovementError::InvalidButtonMask);
        }
        if self.modifiers > 0b111 {
            return Err(PackedMovementError::InvalidModifiers);
        }

        let mut data = [0_u8; BYTES];
        data[0] = MAGIC;
        data[1] = (self.button_mask << 2) | (self.modifiers << 5);
        data[2..4].copy_from_slice(&self.lease_epoch_low.to_le_bytes());
        data[4..8].copy_from_slice(&self.seq.to_le_bytes());
        data[8..12].copy_from_slice(&self.x.to_bits().to_le_bytes());
        data[12..16].copy_from_slice(&self.y.to_bits().to_le_bytes());
        Ok(data)
    }

    pub fn decode(data: &[u8]) -> Result<Self, PackedMovementError> {
        if data.len() != BYTES {
            return Err(PackedMovementError::InvalidLength);
        }
        if data[0] != MAGIC {
            return Err(PackedMovementError::InvalidMagic);
        }

        let flags = data[1];
        if flags & 0b11 != 0 {
            return Err(PackedMovementError::EdgeNotAllowed);
        }

        let x = f32::from_bits(read_u32(data, 8));
        let y = f32::from_bits(read_u32(data, 12));
        if !x.is_finite()
            || !y.is_finite()
            || !(0.0..=1.0).contains(&x)
            || !(0.0..=1.0).contains(&y)
        {
            return Err(PackedMovementError::InvalidCoordinates);
        }

        Ok(Self {
            lease_epoch_low: read_u16(data, 2),
            seq: read_u32(data, 4),
            x,
            y,
            button_mask: (flags >> 2) & 0b111,
            modifiers: (flags >> 5) & 0b111,
        })
    }
}

fn read_u16(data: &[u8], offset: usize) -> u16 {
    u16::from_le_bytes([data[offset], data[offset + 1]])
}

fn read_u32(data: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(data[offset..offset + 4].try_into().unwrap())
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE_HEX: &str = "a52407002a0000000000803e0000403f";

    fn hex(value: &str) -> Vec<u8> {
        (0..value.len())
            .step_by(2)
            .map(|index| u8::from_str_radix(&value[index..index + 2], 16).unwrap())
            .collect()
    }

    #[test]
    fn shared_fixture_decodes() {
        let frame = PackedMovementFrame::decode(&hex(FIXTURE_HEX)).unwrap();
        assert_eq!(
            frame,
            PackedMovementFrame {
                lease_epoch_low: 7,
                seq: 42,
                x: 0.25,
                y: 0.75,
                button_mask: 1,
                modifiers: MODIFIER_SHIFT,
            }
        );
    }

    #[test]
    fn fixture_round_trips_byte_for_byte() {
        let bytes = hex(FIXTURE_HEX);
        assert_eq!(
            PackedMovementFrame::decode(&bytes)
                .unwrap()
                .encode()
                .unwrap()
                .as_slice(),
            bytes.as_slice()
        );
    }

    #[test]
    fn malformed_and_edge_frames_are_rejected() {
        assert_eq!(
            PackedMovementFrame::decode(&[0; BYTES]),
            Err(PackedMovementError::InvalidMagic)
        );

        let mut edge = hex(FIXTURE_HEX);
        edge[1] = 0b01;
        assert_eq!(
            PackedMovementFrame::decode(&edge),
            Err(PackedMovementError::EdgeNotAllowed)
        );

        let mut coordinates = hex(FIXTURE_HEX);
        coordinates[8..12].copy_from_slice(&2.0_f32.to_bits().to_le_bytes());
        assert_eq!(
            PackedMovementFrame::decode(&coordinates),
            Err(PackedMovementError::InvalidCoordinates)
        );

        assert_eq!(
            PackedMovementFrame::decode(&[MAGIC; 15]),
            Err(PackedMovementError::InvalidLength)
        );
    }
}
