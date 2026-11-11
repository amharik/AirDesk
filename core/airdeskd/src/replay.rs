use std::collections::VecDeque;

pub const MAX_CHUNK_BYTES: usize = 8 * 1024;
pub const DEFAULT_MAX_REPLAY_BYTES: usize = 256 * 1024;
pub const DEFAULT_MAX_REPLAY_CHUNKS: usize = 4096;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReplayChunk {
    pub sequence: u64,
    pub data: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReplayResult {
    pub oldest_sequence: u64,
    pub next_sequence: u64,
    pub truncated: bool,
    pub chunks: Vec<ReplayChunk>,
}

#[derive(Debug)]
pub struct ReplayBuffer {
    max_bytes: usize,
    max_chunks: usize,
    chunks: VecDeque<ReplayChunk>,
    bytes: usize,
    next_sequence: u64,
}

impl ReplayBuffer {
    pub fn new(max_bytes: usize, max_chunks: usize) -> Self {
        let max_bytes = max_bytes.max(1);
        let max_chunks = max_chunks.max(1);
        Self {
            max_bytes,
            max_chunks,
            chunks: VecDeque::new(),
            bytes: 0,
            next_sequence: 1,
        }
    }

    pub fn oldest_sequence(&self) -> u64 {
        self.chunks
            .front()
            .map(|chunk| chunk.sequence)
            .unwrap_or(self.next_sequence)
    }

    pub fn next_sequence(&self) -> u64 {
        self.next_sequence
    }

    pub fn retained_bytes(&self) -> usize {
        self.bytes
    }

    pub fn retained_chunks(&self) -> usize {
        self.chunks.len()
    }

    pub fn push(&mut self, data: &[u8]) -> Vec<ReplayChunk> {
        let mut appended = Vec::new();
        for slice in data.chunks(MAX_CHUNK_BYTES.min(self.max_bytes)) {
            let chunk = ReplayChunk {
                sequence: self.next_sequence,
                data: slice.to_vec(),
            };
            self.next_sequence = self.next_sequence.saturating_add(1);
            self.bytes += chunk.data.len();
            self.chunks.push_back(chunk.clone());
            appended.push(chunk);
            self.trim();
        }
        appended
    }

    pub fn after(&self, after_sequence: u64) -> ReplayResult {
        let oldest_sequence = self.oldest_sequence();
        let truncated = if after_sequence == 0 {
            oldest_sequence > 1
        } else {
            after_sequence.saturating_add(1) < oldest_sequence
        };
        let chunks = self
            .chunks
            .iter()
            .filter(|chunk| chunk.sequence > after_sequence)
            .cloned()
            .collect();
        ReplayResult {
            oldest_sequence,
            next_sequence: self.next_sequence,
            truncated,
            chunks,
        }
    }

    fn trim(&mut self) {
        while self.bytes > self.max_bytes || self.chunks.len() > self.max_chunks {
            let Some(chunk) = self.chunks.pop_front() else {
                break;
            };
            self.bytes = self.bytes.saturating_sub(chunk.data.len());
        }
    }
}
