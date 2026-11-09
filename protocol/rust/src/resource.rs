use std::fmt;

use crate::fb::{
    BindMode, BlobAlgorithm, BlobHandle, Qid, ResourceCompoundRequest, ResourceCompoundResult,
    ResourceOpCode, ResourceRpc, ResourceRpcPayload, ResourceStat, ResourceStatus,
};

pub const RESOURCE_INLINE_LIMIT: usize = 64 * 1024;
pub const BLOB_HANDLE_VERSION: u32 = 1;
pub const BLAKE3_DIGEST_BYTES: usize = 32;
pub const RESOURCE_MAX_PATH_SEGMENTS: usize = 32;
const MAX_PATH_SEGMENT_BYTES: usize = 255;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ResourceError {
    InvalidFlatBuffer(String),
    WrongOpCode,
    WrongPayload,
    MissingPayload,
    UnsupportedBlobVersion,
    UnsupportedBlobAlgorithm,
    InvalidBlobDigest,
    InvalidBlobLength,
    InlineTooLarge,
    AmbiguousPayload,
    InvalidPathSegment,
    TooManyPathSegments,
}

impl fmt::Display for ResourceError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidFlatBuffer(message) => write!(formatter, "invalid resource FlatBuffer: {message}"),
            Self::WrongOpCode => write!(formatter, "expected resource compound op code"),
            Self::WrongPayload => write!(formatter, "expected resource compound payload"),
            Self::MissingPayload => write!(formatter, "missing resource payload"),
            Self::UnsupportedBlobVersion => write!(formatter, "unsupported blob handle version"),
            Self::UnsupportedBlobAlgorithm => write!(formatter, "unsupported blob digest algorithm"),
            Self::InvalidBlobDigest => write!(formatter, "blake3 digest must be 32 bytes"),
            Self::InvalidBlobLength => write!(formatter, "invalid blob length"),
            Self::InlineTooLarge => write!(formatter, "inline result exceeds 64 KiB; return a blob handle"),
            Self::AmbiguousPayload => write!(formatter, "result cannot carry both inline data and a blob handle"),
            Self::InvalidPathSegment => write!(formatter, "invalid path segment"),
            Self::TooManyPathSegments => write!(formatter, "too many path segments"),
        }
    }
}

impl std::error::Error for ResourceError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QidData {
    pub kind: u8,
    pub version: u32,
    pub path: u64,
}

impl From<&Qid> for QidData {
    fn from(qid: &Qid) -> Self {
        Self {
            kind: qid.type_(),
            version: qid.version(),
            path: qid.path(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlobHandleData {
    pub version: u32,
    pub algorithm: u8,
    pub digest: Vec<u8>,
    pub length: u64,
    pub expires_at: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResourceStatData {
    pub qid: Option<QidData>,
    pub mode: u32,
    pub length: u64,
    pub name: String,
    pub modified_at: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CompoundRequest {
    pub request_id: u64,
    pub fid: u32,
    pub new_fid: u32,
    pub wnames: Vec<String>,
    pub open_mode: BindMode,
    pub read_offset: u64,
    pub read_count: u32,
    pub clunk: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CompoundResult {
    pub request_id: u64,
    pub status: ResourceStatus,
    pub qid: Option<QidData>,
    pub iounit: u32,
    pub data: Vec<u8>,
    pub blob: Option<BlobHandleData>,
    pub stat: Option<ResourceStatData>,
    pub clunk_status: ResourceStatus,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReadResult {
    pub data: Vec<u8>,
    pub blob: Option<BlobHandleData>,
}

pub fn validate_path_segments(wnames: &[String]) -> Result<(), ResourceError> {
    if wnames.len() > RESOURCE_MAX_PATH_SEGMENTS {
        return Err(ResourceError::TooManyPathSegments);
    }
    for name in wnames {
        if name.is_empty()
            || name.len() > MAX_PATH_SEGMENT_BYTES
            || name == "."
            || name == ".."
            || name.contains('/')
        {
            return Err(ResourceError::InvalidPathSegment);
        }
    }
    Ok(())
}

pub fn validate_blob(handle: &BlobHandleData) -> Result<(), ResourceError> {
    if handle.version != BLOB_HANDLE_VERSION {
        return Err(ResourceError::UnsupportedBlobVersion);
    }
    if handle.algorithm != BlobAlgorithm::blake3.0 {
        return Err(ResourceError::UnsupportedBlobAlgorithm);
    }
    if handle.digest.len() != BLAKE3_DIGEST_BYTES {
        return Err(ResourceError::InvalidBlobDigest);
    }
    if handle.length == 0 {
        return Err(ResourceError::InvalidBlobLength);
    }
    Ok(())
}

pub fn validate_compound_request(request: &CompoundRequest) -> Result<(), ResourceError> {
    validate_path_segments(&request.wnames)
}

pub fn validate_compound_result(result: &CompoundResult) -> Result<(), ResourceError> {
    if result.data.len() > RESOURCE_INLINE_LIMIT {
        return Err(ResourceError::InlineTooLarge);
    }
    if !result.data.is_empty() && result.blob.is_some() {
        return Err(ResourceError::AmbiguousPayload);
    }
    if let Some(blob) = &result.blob {
        validate_blob(blob)?;
    }
    Ok(())
}

pub fn validate_read_result(result: &ReadResult) -> Result<(), ResourceError> {
    if result.data.len() > RESOURCE_INLINE_LIMIT {
        return Err(ResourceError::InlineTooLarge);
    }
    if !result.data.is_empty() && result.blob.is_some() {
        return Err(ResourceError::AmbiguousPayload);
    }
    if let Some(blob) = &result.blob {
        validate_blob(blob)?;
    }
    Ok(())
}

fn root_rpc(data: &[u8]) -> Result<ResourceRpc<'_>, ResourceError> {
    flatbuffers::root::<ResourceRpc>(data)
        .map_err(|error| ResourceError::InvalidFlatBuffer(error.to_string()))
}

fn decode_blob(handle: &BlobHandle<'_>) -> BlobHandleData {
    BlobHandleData {
        version: handle.version(),
        algorithm: handle.algorithm().0,
        digest: handle
            .digest()
            .map(|digest| digest.iter().collect())
            .unwrap_or_default(),
        length: handle.length(),
        expires_at: handle.expires_at(),
    }
}

fn decode_stat(stat: &ResourceStat<'_>) -> ResourceStatData {
    ResourceStatData {
        qid: stat.qid().map(QidData::from),
        mode: stat.mode(),
        length: stat.length(),
        name: stat.name().unwrap_or_default().to_string(),
        modified_at: stat.modified_at(),
    }
}

fn request_from_table(request: ResourceCompoundRequest<'_>) -> Result<CompoundRequest, ResourceError> {
    let wnames = request
        .wnames()
        .map(|names| (0..names.len()).map(|index| names.get(index).to_string()).collect())
        .unwrap_or_default();
    let decoded = CompoundRequest {
        request_id: request.request_id(),
        fid: request.fid(),
        new_fid: request.new_fid(),
        wnames,
        open_mode: request.open_mode(),
        read_offset: request.read_offset(),
        read_count: request.read_count(),
        clunk: request.clunk(),
    };
    validate_compound_request(&decoded)?;
    Ok(decoded)
}

pub fn decode_compound_request(data: &[u8]) -> Result<CompoundRequest, ResourceError> {
    let rpc = root_rpc(data)?;
    if rpc.op_code() != ResourceOpCode::compound {
        return Err(ResourceError::WrongOpCode);
    }
    if rpc.payload_type() != ResourceRpcPayload::ResourceCompoundRequest {
        return Err(ResourceError::WrongPayload);
    }
    let request = rpc
        .payload_as_resource_compound_request()
        .ok_or(ResourceError::MissingPayload)?;
    request_from_table(request)
}

fn result_from_table(result: ResourceCompoundResult<'_>) -> Result<CompoundResult, ResourceError> {
    let decoded = CompoundResult {
        request_id: result.request_id(),
        status: result.status(),
        qid: result.qid().map(QidData::from),
        iounit: result.iounit(),
        data: result
            .data()
            .map(|data| data.iter().collect())
            .unwrap_or_default(),
        blob: result.blob().map(|blob| decode_blob(&blob)),
        stat: result.stat().map(|stat| decode_stat(&stat)),
        clunk_status: result.clunk_status(),
    };
    validate_compound_result(&decoded)?;
    Ok(decoded)
}

pub fn decode_compound_result(data: &[u8]) -> Result<CompoundResult, ResourceError> {
    let rpc = root_rpc(data)?;
    if rpc.op_code() != ResourceOpCode::compound_result {
        return Err(ResourceError::WrongOpCode);
    }
    if rpc.payload_type() != ResourceRpcPayload::ResourceCompoundResult {
        return Err(ResourceError::WrongPayload);
    }
    let result = rpc
        .payload_as_resource_compound_result()
        .ok_or(ResourceError::MissingPayload)?;
    result_from_table(result)
}

pub fn decode_read_result(data: &[u8]) -> Result<ReadResult, ResourceError> {
    let rpc = root_rpc(data)?;
    if rpc.op_code() != ResourceOpCode::read_result
        || rpc.payload_type() != ResourceRpcPayload::ResourceReadResult
    {
        return Err(ResourceError::WrongPayload);
    }
    let result = rpc
        .payload_as_resource_read_result()
        .ok_or(ResourceError::MissingPayload)?;
    let decoded = ReadResult {
        data: result
            .data()
            .map(|data| data.iter().collect())
            .unwrap_or_default(),
        blob: result.blob().map(|blob| decode_blob(&blob)),
    };
    validate_read_result(&decoded)?;
    Ok(decoded)
}

#[cfg(test)]
mod tests {
    use super::*;

    const REQUEST_HEX: &str = "140000000000000000000a000e000d00080004000a0000007400000018000000001112002000140010000c00080000000000040012000000200000001800000008000000070000002a0000000000000000000000020000001800000004000000090000006e6f7465732e74787400000009000000646f63756d656e7473000000";
    const RESULT_HEX: &str = "140000000000000000000a000e000d00080004000a0000007500000018000000001212002a001c0000000c0000000800000004001200000034000000740000000000000003000000b168de3a000000002a000000000000000000000000000e003400240020001400100004000e0000007b68e5cf8b0100000000000024000000190000000000000000000000a48100000000000003000000b168de3a00000000090000006e6f7465732e7478740000001900000068656c6c6f2066726f6d20636f6d706f756e6420726561640a000000";
    const BLOB_RESULT_HEX: &str = "1000000000000a0010000f00080004000a0000007500000018000000000000121000260018000000080000000000040010000000300000000000000004000000b268de3a000000002b000000000000000000000000000e0018000000000014000c0004000e000000c08feecf8b01000000000200000000000400000020000000af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262";
    const READ_BLOB_HEX: &str = "140000000000000000000a0010000f00080004000a0000006b000000100000000000000808000a0000000400080000001400000000000e0018000000000014000c0004000e000000c08feecf8b01000000000200000000000400000020000000af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262";
    const READ_SMALL_HEX: &str = "1000000000000a000e000d00080004000a0000006b0000000c000000000806000800040006000000040000000d000000736d616c6c207061796c6f6164000000";

    fn hex(value: &str) -> Vec<u8> {
        (0..value.len())
            .step_by(2)
            .map(|index| u8::from_str_radix(&value[index..index + 2], 16).unwrap())
            .collect()
    }

    #[test]
    fn compound_request_fixture_decodes() {
        let request = decode_compound_request(&hex(REQUEST_HEX)).unwrap();
        assert_eq!(request.request_id, 42);
        assert_eq!(request.fid, 7);
        assert_eq!(request.new_fid, 8);
        assert_eq!(request.wnames, vec!["documents", "notes.txt"]);
        assert_eq!(request.open_mode, BindMode::read_only);
        assert_eq!(request.read_offset, 0);
        assert_eq!(request.read_count, 32);
        assert!(request.clunk);
    }

    #[test]
    fn inline_compound_result_fixture_decodes() {
        let result = decode_compound_result(&hex(RESULT_HEX)).unwrap();
        assert_eq!(result.request_id, 42);
        assert_eq!(result.qid, Some(QidData { kind: 0, version: 3, path: 987_654_321 }));
        assert_eq!(result.data, b"hello from compound read\n");
        assert!(result.blob.is_none());
        assert_eq!(result.stat.as_ref().unwrap().name, "notes.txt");
        assert_eq!(result.stat.as_ref().unwrap().length, 25);
        assert_eq!(result.clunk_status, ResourceStatus::ok);
    }

    #[test]
    fn large_compound_result_returns_blake3_handle() {
        let result = decode_compound_result(&hex(BLOB_RESULT_HEX)).unwrap();
        assert!(result.data.is_empty());
        let blob = result.blob.unwrap();
        assert_eq!(blob.version, BLOB_HANDLE_VERSION);
        assert_eq!(blob.algorithm, BlobAlgorithm::blake3.0);
        assert_eq!(blob.digest.len(), BLAKE3_DIGEST_BYTES);
        assert_eq!(blob.length, 131_072);
        assert_eq!(blob.expires_at, 1_700_000_600_000);
    }

    #[test]
    fn read_result_fixtures_decode() {
        let large = decode_read_result(&hex(READ_BLOB_HEX)).unwrap();
        assert!(large.data.is_empty());
        assert_eq!(large.blob.unwrap().length, 131_072);

        let small = decode_read_result(&hex(READ_SMALL_HEX)).unwrap();
        assert_eq!(small.data, b"small payload");
        assert!(small.blob.is_none());
    }

    #[test]
    fn bounds_and_path_validation_reject_ambiguous_payloads() {
        let blob = BlobHandleData {
            version: BLOB_HANDLE_VERSION,
            algorithm: BlobAlgorithm::blake3.0,
            digest: vec![0; BLAKE3_DIGEST_BYTES],
            length: 1,
            expires_at: 0,
        };
        assert_eq!(
            validate_read_result(&ReadResult {
                data: vec![0; RESOURCE_INLINE_LIMIT + 1],
                blob: None,
            }),
            Err(ResourceError::InlineTooLarge)
        );
        assert_eq!(
            validate_read_result(&ReadResult {
                data: vec![1],
                blob: Some(blob.clone()),
            }),
            Err(ResourceError::AmbiguousPayload)
        );
        assert_eq!(
            validate_blob(&BlobHandleData {
                digest: vec![0; 31],
                ..blob
            }),
            Err(ResourceError::InvalidBlobDigest)
        );
        assert_eq!(
            validate_path_segments(&["..".to_string()]),
            Err(ResourceError::InvalidPathSegment)
        );
        assert_eq!(
            validate_path_segments(&vec!["x".to_string(); RESOURCE_MAX_PATH_SEGMENTS + 1]),
            Err(ResourceError::TooManyPathSegments)
        );
    }
}
