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

pub const ONE_EURO_MINIMUM_DELTA_TIME: f64 = 1.0 / 240.0;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct OneEuroParameters {
    pub min_cutoff: f64,
    pub beta: f64,
    pub d_cutoff: f64,
}

impl Default for OneEuroParameters {
    fn default() -> Self {
        Self {
            min_cutoff: 1.0,
            beta: 160.0,
            d_cutoff: 1.0,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OneEuroFilterError {
    InvalidParameters,
    NonFiniteInput,
}

impl fmt::Display for OneEuroFilterError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{self:?}")
    }
}

impl std::error::Error for OneEuroFilterError {}

#[derive(Debug, Clone, Copy, PartialEq)]
struct OneEuroAxis {
    previous: f64,
    filtered: f64,
    derivative: f64,
}

impl OneEuroAxis {
    const fn new() -> Self {
        Self {
            previous: 0.0,
            filtered: 0.0,
            derivative: 0.0,
        }
    }

    fn reset(&mut self) {
        *self = Self::new();
    }

    fn seed(&mut self, value: f64) {
        self.previous = value;
        self.filtered = value;
        self.derivative = 0.0;
    }

    fn filter(&mut self, value: f64, delta_time: f64, parameters: OneEuroParameters) -> f64 {
        let raw_derivative = (value - self.previous) / delta_time;
        let derivative_alpha = axis_alpha(parameters.d_cutoff, delta_time);
        self.derivative = low_pass(raw_derivative, self.derivative, derivative_alpha);
        let cutoff = parameters.min_cutoff + parameters.beta * self.derivative.abs();
        let value_alpha = axis_alpha(cutoff, delta_time);
        let output = low_pass(value, self.filtered, value_alpha);
        self.previous = value;
        self.filtered = output;
        output
    }
}

fn axis_alpha(cutoff: f64, delta_time: f64) -> f64 {
    if !cutoff.is_finite() || cutoff <= 0.0 || !delta_time.is_finite() || delta_time <= 0.0 {
        return 1.0;
    }
    let time_constant = 1.0 / (2.0 * std::f64::consts::PI * cutoff);
    1.0 / (1.0 + time_constant / delta_time)
}

fn low_pass(input: f64, previous: f64, alpha: f64) -> f64 {
    alpha * input + (1.0 - alpha) * previous
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct OneEuroFilter {
    parameters: OneEuroParameters,
    x_axis: OneEuroAxis,
    y_axis: OneEuroAxis,
    last_timestamp: Option<f64>,
}

impl OneEuroFilter {
    pub fn new(parameters: OneEuroParameters) -> Result<Self, OneEuroFilterError> {
        if !parameters.min_cutoff.is_finite()
            || parameters.min_cutoff <= 0.0
            || !parameters.beta.is_finite()
            || parameters.beta < 0.0
            || !parameters.d_cutoff.is_finite()
            || parameters.d_cutoff <= 0.0
        {
            return Err(OneEuroFilterError::InvalidParameters);
        }
        Ok(Self {
            parameters,
            x_axis: OneEuroAxis::new(),
            y_axis: OneEuroAxis::new(),
            last_timestamp: None,
        })
    }

    pub fn reset(&mut self) {
        self.x_axis.reset();
        self.y_axis.reset();
        self.last_timestamp = None;
    }

    pub fn filter(
        &mut self,
        x: f64,
        y: f64,
        timestamp: f64,
    ) -> Result<(f64, f64), OneEuroFilterError> {
        if !x.is_finite() || !y.is_finite() || !timestamp.is_finite() {
            return Err(OneEuroFilterError::NonFiniteInput);
        }
        let Some(previous_timestamp) = self.last_timestamp else {
            self.x_axis.seed(x);
            self.y_axis.seed(y);
            self.last_timestamp = Some(timestamp);
            return Ok((x, y));
        };
        let delta_time = (timestamp - previous_timestamp).max(ONE_EURO_MINIMUM_DELTA_TIME);
        self.last_timestamp = Some(timestamp);
        Ok((
            self.x_axis.filter(x, delta_time, self.parameters),
            self.y_axis.filter(y, delta_time, self.parameters),
        ))
    }

    pub fn parameters(&self) -> OneEuroParameters {
        self.parameters
    }
}

#[cfg(test)]
mod one_euro_tests {
    use super::*;

    const FIXTURE: &str = include_str!("../../../protocol/fixtures/input/one-euro-v1.json");

    #[derive(Debug, Clone, Copy)]
    struct Sample {
        t: f64,
        x: f64,
        y: f64,
    }

    fn case_section(name: &str) -> &'static str {
        let marker = format!("\"name\": \"{name}\"");
        let start = FIXTURE.find(&marker).expect("fixture case");
        let next = FIXTURE[start + marker.len()..]
            .find("\"name\":")
            .map(|offset| start + marker.len() + offset)
            .unwrap_or(FIXTURE.len());
        &FIXTURE[start..next]
    }

    fn array_after<'a>(key: &str, section: &'a str) -> &'a str {
        let marker = format!("\"{key}\": [");
        let start = section.find(&marker).expect("fixture array") + marker.len();
        let end = section[start..].find(']').expect("fixture array end") + start;
        &section[start..end]
    }

    fn number_after(marker: &str, source: &str) -> f64 {
        let start = source.find(marker).expect("fixture number") + marker.len();
        let rest = source[start..].trim_start();
        let end = rest
            .find(|character: char| {
                character == ','
                    || character == '}'
                    || character == ']'
                    || character.is_whitespace()
            })
            .unwrap_or(rest.len());
        rest[..end].parse().expect("fixture number value")
    }

    fn samples(array: &str) -> Vec<Sample> {
        array
            .split('}')
            .filter(|chunk| chunk.contains("\"x\":"))
            .map(|chunk| Sample {
                t: number_after("\"t\":", chunk),
                x: number_after("\"x\":", chunk),
                y: number_after("\"y\":", chunk),
            })
            .collect()
    }

    fn parameters() -> OneEuroParameters {
        OneEuroParameters {
            min_cutoff: number_after("\"min_cutoff\":", FIXTURE),
            beta: number_after("\"beta\":", FIXTURE),
            d_cutoff: number_after("\"d_cutoff\":", FIXTURE),
        }
    }

    fn run(name: &str) -> (Vec<Sample>, Vec<Sample>, OneEuroParameters) {
        let section = case_section(name);
        let input = samples(array_after("samples", section));
        let expected = samples(array_after("expected", section));
        (input, expected, parameters())
    }

    #[test]
    fn fixture_matches_shared_filter_outputs() {
        let (input, expected, parameters) = run("low-speed-jitter");
        assert_eq!(parameters, OneEuroParameters::default());
        assert_eq!(input.len(), expected.len());

        let mut filter = OneEuroFilter::new(parameters).unwrap();
        for (sample, expected) in input.iter().zip(expected.iter()) {
            let (x, y) = filter.filter(sample.x, sample.y, sample.t).unwrap();
            assert!((x - expected.x).abs() < 1e-9);
            assert!((y - expected.y).abs() < 1e-9);
        }
    }

    #[test]
    fn high_speed_tracking_has_no_material_phase_lag() {
        let (input, _, _) = run("high-speed-tracking");
        let mut filter = OneEuroFilter::new(OneEuroParameters::default()).unwrap();
        let errors: Vec<f64> = input
            .iter()
            .map(|sample| {
                let (x, y) = filter.filter(sample.x, sample.y, sample.t).unwrap();
                (x - sample.x).hypot(y - sample.y)
            })
            .collect();
        let warmup = &errors[10..];
        assert!(warmup.iter().copied().fold(0.0_f64, f64::max) < 0.005);
        assert!(errors.last().copied().unwrap() < 0.003);
    }

    #[test]
    fn low_speed_jitter_is_attenuated() {
        let (input, _, _) = run("low-speed-jitter");
        let mut filter = OneEuroFilter::new(OneEuroParameters::default()).unwrap();
        let outputs: Vec<f64> = input
            .iter()
            .map(|sample| filter.filter(sample.x, sample.y, sample.t).unwrap().0)
            .collect();
        let filtered = &outputs[10..];
        let raw = &input[10..];
        let filtered_range = filtered.iter().copied().fold(f64::NEG_INFINITY, f64::max)
            - filtered.iter().copied().fold(f64::INFINITY, f64::min);
        let raw_range = raw
            .iter()
            .map(|sample| sample.x)
            .fold(f64::NEG_INFINITY, f64::max)
            - raw
                .iter()
                .map(|sample| sample.x)
                .fold(f64::INFINITY, f64::min);
        assert!(raw_range > 0.0);
        assert!(filtered_range < raw_range * 0.2);
    }

    #[test]
    fn reset_and_invalid_parameters_behave() {
        let mut filter = OneEuroFilter::new(OneEuroParameters::default()).unwrap();
        filter.filter(0.2, 0.3, 0.0).unwrap();
        filter.filter(0.8, 0.7, 1.0 / 120.0).unwrap();
        filter.reset();
        assert_eq!(filter.filter(0.6, 0.4, 2.0 / 120.0).unwrap(), (0.6, 0.4));

        assert_eq!(
            OneEuroFilter::new(OneEuroParameters {
                min_cutoff: 0.0,
                ..OneEuroParameters::default()
            }),
            Err(OneEuroFilterError::InvalidParameters)
        );
        assert_eq!(
            OneEuroFilter::new(OneEuroParameters {
                beta: -1.0,
                ..OneEuroParameters::default()
            }),
            Err(OneEuroFilterError::InvalidParameters)
        );
        assert_eq!(
            OneEuroFilter::new(OneEuroParameters {
                d_cutoff: 0.0,
                ..OneEuroParameters::default()
            }),
            Err(OneEuroFilterError::InvalidParameters)
        );
        assert_eq!(
            filter.filter(f64::NAN, 0.5, 0.0),
            Err(OneEuroFilterError::NonFiniteInput)
        );
    }
}
