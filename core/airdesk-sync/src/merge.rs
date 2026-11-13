//! Snapshot-to-operation bridging for the P4-11 platform cutover.
//!
//! Platform snapshots still carry the existing `revision`/`deviceId` field
//! wrappers. This module translates those snapshots into operation logs, uses
//! the core `(lamport, actor, id)` order to pick LWW and append-log winners,
//! and emits the platform-shaped apply result. Manual fields stay explicit
//! conflicts; callers must resolve them before they can be applied.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::{
    FieldMetadata, MergeClass, MergeRegistry, Operation, OperationLog, SyncError, MAX_ACTOR_BYTES,
};

fn default_schema_version() -> i64 {
    1
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncSnapshot {
    pub workspace_id: String,
    pub host_epoch: u64,
    pub workspace_seq: u64,
    pub revision: u64,
    pub fields: BTreeMap<String, Value>,
    #[serde(default)]
    pub metadata: Vec<SyncMetadata>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncMetadata {
    pub path: String,
    pub merge: MergeClass,
    #[serde(default = "default_schema_version")]
    pub since_schema_version: i64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SyncStatus {
    Applied,
    Unchanged,
    Conflict,
    Rejected,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SyncFieldStatus {
    Merged,
    Unchanged,
    Conflict,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SyncWinner {
    Local,
    Remote,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum SyncRejectReason {
    WorkspaceMismatch,
    StaleEpoch,
    FutureEpoch,
    StaleSeq,
    FutureSeq,
    StaleRevision,
    InvalidPatch,
    Interrupted,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum SyncConflictReason {
    ManualMerge,
    UnclassifiedField,
    AmbiguousLww,
    AppendLogDuplicateConflict,
    InvalidValue,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncConflict {
    pub path: String,
    pub merge: MergeClass,
    pub reason: SyncConflictReason,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub local: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub remote: Option<Value>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncFieldResult {
    pub path: String,
    pub merge: MergeClass,
    pub status: SyncFieldStatus,
    pub changed: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub winner: Option<SyncWinner>,
    #[serde(default)]
    pub conflicts: Vec<SyncConflict>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyncApplyResult {
    pub status: SyncStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<SyncRejectReason>,
    pub snapshot: SyncSnapshot,
    pub field_results: Vec<SyncFieldResult>,
    pub conflicts: Vec<SyncConflict>,
}

/// Merge two platform snapshots through the shared operation log.
pub fn merge_snapshots_json(local_json: &str, remote_json: &str) -> Result<String, SyncError> {
    let local: SyncSnapshot = serde_json::from_str(local_json)
        .map_err(|error| SyncError::InvalidSnapshot(error.to_string()))?;
    let remote: SyncSnapshot = serde_json::from_str(remote_json)
        .map_err(|error| SyncError::InvalidSnapshot(error.to_string()))?;
    let result = merge_snapshots(&local, &remote)?;
    serde_json::to_string(&result).map_err(|error| SyncError::Serialization(error.to_string()))
}

pub fn merge_snapshots(
    local: &SyncSnapshot,
    remote: &SyncSnapshot,
) -> Result<SyncApplyResult, SyncError> {
    if local.workspace_id != remote.workspace_id {
        return Ok(rejected(local, SyncRejectReason::WorkspaceMismatch));
    }
    if remote.host_epoch < local.host_epoch {
        return Ok(rejected(local, SyncRejectReason::StaleEpoch));
    }
    if remote.host_epoch > local.host_epoch {
        return Ok(rejected(local, SyncRejectReason::FutureEpoch));
    }

    let metadata = combined_metadata(local, remote);
    let registry = MergeRegistry::new(metadata.iter().map(|entry| FieldMetadata {
        path: entry.path.clone(),
        merge: entry.merge,
    }))?;

    let paths: BTreeSet<String> = local
        .fields
        .keys()
        .chain(remote.fields.keys())
        .cloned()
        .collect();
    let mut next_fields = local.fields.clone();
    let mut field_results = Vec::with_capacity(paths.len());

    for path in &paths {
        let merge = registry.merge_class(path);
        let result = merge_path(
            path,
            merge,
            registry.is_registered(path),
            local.fields.get(path),
            remote.fields.get(path),
        )?;
        if let Some(value) = &result.value {
            next_fields.insert(path.clone(), value.clone());
        }
        field_results.push(result);
    }

    let conflicts = field_results
        .iter()
        .flat_map(|result| result.conflicts.iter().cloned())
        .collect::<Vec<_>>();
    if !conflicts.is_empty() {
        return Ok(SyncApplyResult {
            status: SyncStatus::Conflict,
            reason: None,
            snapshot: local.clone(),
            field_results,
            conflicts,
        });
    }

    if !field_results.iter().any(|result| result.changed) {
        return Ok(SyncApplyResult {
            status: SyncStatus::Unchanged,
            reason: None,
            snapshot: local.clone(),
            field_results,
            conflicts: Vec::new(),
        });
    }

    let mut snapshot = local.clone();
    snapshot.workspace_seq = local.workspace_seq.max(remote.workspace_seq) + 1;
    snapshot.revision = local.revision.max(remote.revision) + 1;
    snapshot.fields = next_fields;
    snapshot.metadata = metadata;
    Ok(SyncApplyResult {
        status: SyncStatus::Applied,
        reason: None,
        snapshot,
        field_results,
        conflicts: Vec::new(),
    })
}

fn combined_metadata(local: &SyncSnapshot, remote: &SyncSnapshot) -> Vec<SyncMetadata> {
    let mut metadata = BTreeMap::new();
    for entry in &remote.metadata {
        metadata.insert(entry.path.clone(), entry.clone());
    }
    for entry in &local.metadata {
        metadata.insert(entry.path.clone(), entry.clone());
    }
    metadata.into_values().collect()
}

fn rejected(local: &SyncSnapshot, reason: SyncRejectReason) -> SyncApplyResult {
    SyncApplyResult {
        status: SyncStatus::Rejected,
        reason: Some(reason),
        snapshot: local.clone(),
        field_results: Vec::new(),
        conflicts: Vec::new(),
    }
}

fn merge_path(
    path: &str,
    merge: MergeClass,
    classified: bool,
    local: Option<&Value>,
    remote: Option<&Value>,
) -> Result<SyncFieldResult, SyncError> {
    match merge {
        MergeClass::Lww => merge_lww(path, local, remote),
        MergeClass::AppendLog => merge_append(path, local, remote),
        MergeClass::Manual => Ok(merge_manual(path, classified, local, remote)),
    }
}

fn merge_lww(
    path: &str,
    local: Option<&Value>,
    remote: Option<&Value>,
) -> Result<SyncFieldResult, SyncError> {
    match (local, remote) {
        (Some(local), None) => Ok(field_result(
            path,
            MergeClass::Lww,
            SyncFieldStatus::Unchanged,
            false,
            Some(local.clone()),
            None,
            Vec::new(),
        )),
        (None, Some(remote)) => Ok(field_result(
            path,
            MergeClass::Lww,
            SyncFieldStatus::Merged,
            true,
            Some(remote.clone()),
            None,
            Vec::new(),
        )),
        (Some(local), Some(remote)) => {
            let local_value = LwwValue::from_json(local);
            let remote_value = LwwValue::from_json(remote);
            let (Some(local_value), Some(remote_value)) = (local_value, remote_value) else {
                return Ok(field_result(
                    path,
                    MergeClass::Lww,
                    SyncFieldStatus::Conflict,
                    false,
                    Some(local.clone()),
                    None,
                    vec![conflict(
                        path,
                        MergeClass::Lww,
                        SyncConflictReason::InvalidValue,
                        Some(local.clone()),
                        Some(remote.clone()),
                    )],
                ));
            };
            if local_value.revision == remote_value.revision
                && local_value.device_id == remote_value.device_id
                && canonical(&local_value.value) != canonical(&remote_value.value)
            {
                return Ok(field_result(
                    path,
                    MergeClass::Lww,
                    SyncFieldStatus::Conflict,
                    false,
                    None,
                    None,
                    vec![conflict(
                        path,
                        MergeClass::Lww,
                        SyncConflictReason::AmbiguousLww,
                        Some(local.clone()),
                        Some(remote.clone()),
                    )],
                ));
            }

            let remote_wins = remote_value.revision > local_value.revision
                || (remote_value.revision == local_value.revision
                    && remote_value.device_id > local_value.device_id);
            let (winner, value, status) = if remote_wins {
                (
                    Some(SyncWinner::Remote),
                    remote_value.json(),
                    SyncFieldStatus::Merged,
                )
            } else {
                (
                    Some(SyncWinner::Local),
                    local_value.json(),
                    SyncFieldStatus::Unchanged,
                )
            };
            Ok(field_result(
                path,
                MergeClass::Lww,
                status,
                winner == Some(SyncWinner::Remote),
                Some(value),
                winner,
                Vec::new(),
            ))
        }
        (None, None) => Ok(field_result(
            path,
            MergeClass::Lww,
            SyncFieldStatus::Unchanged,
            false,
            None,
            None,
            Vec::new(),
        )),
    }
}

fn merge_append(
    path: &str,
    local: Option<&Value>,
    remote: Option<&Value>,
) -> Result<SyncFieldResult, SyncError> {
    let local_entries = local.map(parse_entries).unwrap_or_default();
    let remote_entries = remote.map(parse_entries).unwrap_or_default();
    if local.is_some() && remote.is_none() {
        return Ok(field_result(
            path,
            MergeClass::AppendLog,
            SyncFieldStatus::Unchanged,
            false,
            local.cloned(),
            None,
            Vec::new(),
        ));
    }

    let local_present = local.is_some();
    let local_ids = local_entries
        .iter()
        .map(|entry| entry.id.clone())
        .collect::<BTreeSet<_>>();
    let mut operation_entries = Vec::new();
    for entry in &local_entries {
        operation_entries.push(OperationEntry {
            operation: entry.operation(path)?,
            entry: entry.clone(),
        });
    }
    for entry in &remote_entries {
        operation_entries.push(OperationEntry {
            operation: entry.operation(path)?,
            entry: entry.clone(),
        });
    }

    let mut log = OperationLog::new();
    let mut by_operation_id = BTreeMap::new();
    for item in &operation_entries {
        let id = item.operation.id.clone();
        log.insert(item.operation.clone())?;
        by_operation_id.entry(id).or_insert(item);
    }
    let registry = path_registry(path, MergeClass::AppendLog)?;
    let projected = log.project(&registry)?;
    let winners = projected
        .fields
        .get(path)
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();

    let mut entries = Vec::with_capacity(winners.len());
    for winner in &winners {
        let Some(key) = winner.get("id").and_then(Value::as_str) else {
            continue;
        };
        let Some(value) = winner.get("value") else {
            continue;
        };
        let entry = choose_entry(key, value, &local_entries, &remote_entries);
        if let Some(entry) = entry {
            entries.push(entry.json());
        }
    }
    entries.sort_by(|left, right| {
        let left_revision = left.get("revision").and_then(Value::as_u64).unwrap_or(0);
        let right_revision = right.get("revision").and_then(Value::as_u64).unwrap_or(0);
        left_revision.cmp(&right_revision).then_with(|| {
            left.get("id")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .cmp(right.get("id").and_then(Value::as_str).unwrap_or_default())
        })
    });

    let mut conflicts = Vec::new();
    for conflict_entry in &projected.conflicts {
        let Some(key) = conflict_entry.key.as_deref() else {
            continue;
        };
        let winner = by_operation_id
            .get(&conflict_entry.winner)
            .map(|item| item.entry.clone());
        let loser = conflict_entry
            .losers
            .first()
            .and_then(|id| by_operation_id.get(id))
            .map(|item| item.entry.clone());
        let local_entry = local_entries
            .iter()
            .find(|entry| entry.id == key)
            .cloned()
            .or_else(|| winner.clone());
        let remote_entry = remote_entries
            .iter()
            .find(|entry| entry.id == key)
            .cloned()
            .or(loser);
        conflicts.push(conflict(
            path,
            MergeClass::AppendLog,
            SyncConflictReason::AppendLogDuplicateConflict,
            local_entry.map(|entry| entry.json()),
            remote_entry.map(|entry| entry.json()),
        ));
    }
    let added = winners
        .iter()
        .filter(|winner| {
            winner
                .get("id")
                .and_then(Value::as_str)
                .map(|id| !local_ids.contains(id))
                .unwrap_or(false)
        })
        .count();
    let status = if !conflicts.is_empty() {
        SyncFieldStatus::Conflict
    } else if !local_present || added > 0 {
        SyncFieldStatus::Merged
    } else {
        SyncFieldStatus::Unchanged
    };

    Ok(field_result(
        path,
        MergeClass::AppendLog,
        status,
        added > 0,
        Some(Value::Array(entries)),
        None,
        conflicts,
    ))
}

fn merge_manual(
    path: &str,
    classified: bool,
    local: Option<&Value>,
    remote: Option<&Value>,
) -> SyncFieldResult {
    match (local, remote) {
        (Some(local), None) => field_result(
            path,
            MergeClass::Manual,
            SyncFieldStatus::Unchanged,
            false,
            Some(local.clone()),
            None,
            Vec::new(),
        ),
        (None, Some(remote)) => {
            if !classified {
                return field_result(
                    path,
                    MergeClass::Manual,
                    SyncFieldStatus::Conflict,
                    false,
                    None,
                    None,
                    vec![conflict(
                        path,
                        MergeClass::Manual,
                        SyncConflictReason::UnclassifiedField,
                        None,
                        Some(remote.clone()),
                    )],
                );
            }
            field_result(
                path,
                MergeClass::Manual,
                SyncFieldStatus::Merged,
                true,
                Some(remote.clone()),
                None,
                Vec::new(),
            )
        }
        (Some(local), Some(remote)) => {
            if canonical(local) == canonical(remote) {
                return field_result(
                    path,
                    MergeClass::Manual,
                    SyncFieldStatus::Unchanged,
                    false,
                    Some(local.clone()),
                    None,
                    Vec::new(),
                );
            }
            field_result(
                path,
                MergeClass::Manual,
                SyncFieldStatus::Conflict,
                false,
                Some(local.clone()),
                None,
                vec![conflict(
                    path,
                    MergeClass::Manual,
                    SyncConflictReason::ManualMerge,
                    Some(local.clone()),
                    Some(remote.clone()),
                )],
            )
        }
        (None, None) => field_result(
            path,
            MergeClass::Manual,
            SyncFieldStatus::Unchanged,
            false,
            None,
            None,
            Vec::new(),
        ),
    }
}

fn field_result(
    path: &str,
    merge: MergeClass,
    status: SyncFieldStatus,
    changed: bool,
    value: Option<Value>,
    winner: Option<SyncWinner>,
    conflicts: Vec<SyncConflict>,
) -> SyncFieldResult {
    SyncFieldResult {
        path: path.to_owned(),
        merge,
        status,
        changed,
        value,
        winner,
        conflicts,
    }
}

fn conflict(
    path: &str,
    merge: MergeClass,
    reason: SyncConflictReason,
    local: Option<Value>,
    remote: Option<Value>,
) -> SyncConflict {
    SyncConflict {
        path: path.to_owned(),
        merge,
        reason,
        local,
        remote,
    }
}

fn path_registry(path: &str, merge: MergeClass) -> Result<MergeRegistry, SyncError> {
    MergeRegistry::new([FieldMetadata {
        path: path.to_owned(),
        merge,
    }])
}

#[derive(Clone, Debug)]
struct LwwValue {
    value: Value,
    revision: u64,
    device_id: String,
}

impl LwwValue {
    fn from_json(value: &Value) -> Option<Self> {
        let object = value.as_object()?;
        Some(Self {
            value: object.get("value")?.clone(),
            revision: object.get("revision")?.as_u64()?,
            device_id: object.get("deviceId")?.as_str()?.to_owned(),
        })
    }

    fn json(&self) -> Value {
        json!({
            "value": self.value,
            "revision": self.revision,
            "deviceId": self.device_id,
        })
    }
}

#[derive(Clone, Debug)]
struct AppendEntry {
    id: String,
    value: Value,
    revision: Option<u64>,
}

impl AppendEntry {
    fn from_json(value: &Value) -> Option<Self> {
        let object = value.as_object()?;
        Some(Self {
            id: object.get("id")?.as_str()?.to_owned(),
            value: object.get("value")?.clone(),
            revision: object.get("revision").and_then(Value::as_u64),
        })
    }

    fn json(&self) -> Value {
        let mut object = serde_json::Map::new();
        object.insert("id".into(), Value::String(self.id.clone()));
        object.insert("value".into(), self.value.clone());
        if let Some(revision) = self.revision {
            object.insert("revision".into(), json!(revision));
        }
        Value::Object(object)
    }

    fn operation(&self, path: &str) -> Result<Operation, SyncError> {
        let id = operation_id(
            "append",
            &[
                path,
                &self.id,
                &self.revision.unwrap_or(0).to_string(),
                &canonical(&self.value),
            ],
        );
        Ok(Operation::append_entry(
            id,
            bounded_actor(&self.id),
            self.revision.unwrap_or(1).max(1),
            path.to_owned(),
            self.id.clone(),
            self.value.clone(),
        ))
    }
}

#[derive(Clone)]
struct OperationEntry {
    operation: Operation,
    entry: AppendEntry,
}

fn parse_entries(value: &Value) -> Vec<AppendEntry> {
    value
        .as_array()
        .map(|array| {
            array
                .iter()
                .filter_map(AppendEntry::from_json)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn choose_entry(
    key: &str,
    value: &Value,
    local: &[AppendEntry],
    remote: &[AppendEntry],
) -> Option<AppendEntry> {
    local
        .iter()
        .find(|entry| entry.id == key && canonical(&entry.value) == canonical(value))
        .cloned()
        .or_else(|| {
            remote
                .iter()
                .find(|entry| entry.id == key && canonical(&entry.value) == canonical(value))
                .cloned()
        })
        .or_else(|| local.iter().find(|entry| entry.id == key).cloned())
        .or_else(|| remote.iter().find(|entry| entry.id == key).cloned())
}

fn canonical(value: &Value) -> String {
    serde_json::to_string(value).unwrap_or_default()
}

fn bounded_actor(value: &str) -> String {
    if !value.is_empty() && value.len() <= MAX_ACTOR_BYTES {
        return value.to_owned();
    }
    format!("h:{}", stable_hash(&[value]))
}

fn operation_id(prefix: &str, parts: &[&str]) -> String {
    format!("{prefix}:{}", stable_hash(parts))
}

fn stable_hash(parts: &[&str]) -> String {
    let mut first = 0xcbf2_9ce4_8422_2325_u64;
    let mut second = 0x8422_2325_cbf2_9ce4_u64;
    for part in parts {
        for byte in part.as_bytes() {
            first ^= u64::from(*byte);
            first = first.wrapping_mul(0x0000_0100_0000_01b3);
            second ^= u64::from(*byte);
            second = second.wrapping_mul(0x0000_0100_0000_01b3) ^ first.rotate_left(7);
        }
        first ^= 0xff;
        first = first.wrapping_mul(0x0000_0100_0000_01b3);
        second ^= 0xfe;
        second = second.wrapping_mul(0x0000_0100_0000_01b3);
    }
    format!("{first:016x}{second:016x}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lww_uses_revision_then_actor_and_keeps_ambiguity_explicit() {
        let local = snapshot(
            json!({
                "layout.geometry": {"value": {"x": 1}, "revision": 4, "deviceId": "dev-a"}
            }),
            false,
        );
        let remote = snapshot(
            json!({
                "layout.geometry": {"value": {"x": 2}, "revision": 4, "deviceId": "dev-b"}
            }),
            false,
        );
        let result = merge_snapshots(&local, &remote).expect("merge");
        assert_eq!(result.status, SyncStatus::Applied);
        assert_eq!(
            result.snapshot.fields.get("layout.geometry"),
            Some(&json!({"value": {"x": 2}, "revision": 4, "deviceId": "dev-b"}))
        );

        let ambiguous = merge_snapshots(
            &local,
            &snapshot(
                json!({
                    "layout.geometry": {"value": {"x": 9}, "revision": 4, "deviceId": "dev-a"}
                }),
                false,
            ),
        )
        .expect("merge");
        assert_eq!(ambiguous.status, SyncStatus::Conflict);
        assert_eq!(
            ambiguous.field_results[0].conflicts[0].reason,
            SyncConflictReason::AmbiguousLww
        );
    }

    #[test]
    fn append_log_uses_operation_order_and_reports_duplicate_conflicts() {
        let local = snapshot(
            json!({
                "instances": [
                    {"id": "win-1", "value": {"title": "A"}, "revision": 1},
                    {"id": "win-2", "value": {"title": "A"}, "revision": 2}
                ]
            }),
            false,
        );
        let remote = snapshot(
            json!({
                "instances": [
                    {"id": "win-1", "value": {"title": "A"}, "revision": 1},
                    {"id": "win-2", "value": {"title": "B"}, "revision": 3}
                ]
            }),
            false,
        );
        let result = merge_snapshots(&local, &remote).expect("merge");
        assert_eq!(result.status, SyncStatus::Conflict);
        assert_eq!(
            result.field_results[0].conflicts[0].reason,
            SyncConflictReason::AppendLogDuplicateConflict
        );
        assert_eq!(
            result.field_results[0].value.as_ref().unwrap()[1]["value"]["title"],
            json!("B")
        );
    }

    #[test]
    fn manual_fields_stay_explicit_and_unclassified_fields_are_rejected() {
        let local = snapshot(json!({"owner": "alice"}), true);
        let remote = snapshot(json!({"owner": "bob"}), true);
        let result = merge_snapshots(&local, &remote).expect("merge");
        assert_eq!(result.status, SyncStatus::Conflict);
        assert_eq!(result.conflicts[0].reason, SyncConflictReason::ManualMerge);
        assert_eq!(result.snapshot.fields.get("owner"), Some(&json!("alice")));

        let unclassified = merge_snapshots(
            &snapshot(json!({}), false),
            &snapshot(json!({"owner": "bob"}), false),
        )
        .expect("merge");
        assert_eq!(
            unclassified.conflicts[0].reason,
            SyncConflictReason::UnclassifiedField
        );
    }

    #[test]
    fn snapshot_merges_match_forward_and_reverse_order() {
        let fixture: Value = serde_json::from_str(include_str!(
            "../../../protocol/fixtures/sync/merge-snapshots-v1.json"
        ))
        .expect("merge fixture");
        for case in fixture["cases"].as_array().expect("cases") {
            let local: SyncSnapshot =
                serde_json::from_value(case["local"].clone()).expect("local snapshot");
            let remote: SyncSnapshot =
                serde_json::from_value(case["remote"].clone()).expect("remote snapshot");
            let forward = merge_snapshots(&local, &remote).expect("forward merge");
            let reverse = merge_snapshots(&remote, &local).expect("reverse merge");
            match forward.status {
                SyncStatus::Applied | SyncStatus::Unchanged => {
                    assert!(
                        matches!(reverse.status, SyncStatus::Applied | SyncStatus::Unchanged),
                        "case status"
                    );
                    assert_eq!(
                        forward.snapshot.fields, reverse.snapshot.fields,
                        "case fields"
                    );
                }
                SyncStatus::Conflict | SyncStatus::Rejected => {
                    assert_eq!(forward.status, reverse.status, "case status");
                }
            }
            assert_eq!(
                forward
                    .conflicts
                    .iter()
                    .map(|conflict| conflict.reason)
                    .collect::<Vec<_>>(),
                reverse
                    .conflicts
                    .iter()
                    .map(|conflict| conflict.reason)
                    .collect::<Vec<_>>(),
                "case conflicts"
            );
            let expected_fields: BTreeMap<String, Value> =
                serde_json::from_value(case["expectedFields"].clone()).expect("expected fields");
            assert_eq!(
                forward.snapshot.fields, expected_fields,
                "case expected fields"
            );
        }
    }

    fn snapshot(fields: Value, manual_owner: bool) -> SyncSnapshot {
        let mut metadata = vec![
            SyncMetadata {
                path: "layout.geometry".into(),
                merge: MergeClass::Lww,
                since_schema_version: 1,
            },
            SyncMetadata {
                path: "instances".into(),
                merge: MergeClass::AppendLog,
                since_schema_version: 1,
            },
        ];
        if manual_owner {
            metadata.push(SyncMetadata {
                path: "owner".into(),
                merge: MergeClass::Manual,
                since_schema_version: 1,
            });
        }
        SyncSnapshot {
            workspace_id: "ws-1".into(),
            host_epoch: 3,
            workspace_seq: 4,
            revision: 4,
            fields: serde_json::from_value(fields).expect("fields"),
            metadata,
        }
    }
}
