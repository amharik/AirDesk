//! Deterministic operation-log convergence for workspace synchronization.
//!
//! P4-11 adds a core operation log with Lamport/actor ordering. The platform
//! merge entry points call [`merge_snapshots_json`] behind a feature flag and
//! fall back to the native implementation if the binding fails.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use thiserror::Error;

mod merge;
pub use merge::{merge_snapshots, merge_snapshots_json, SyncApplyResult, SyncSnapshot};

pub const MAX_OPERATION_ID_BYTES: usize = 256;
pub const MAX_ACTOR_BYTES: usize = 128;
pub const MAX_PATH_BYTES: usize = 512;
pub const MAX_ENTRY_KEY_BYTES: usize = 256;

/// How a field is reconciled when concurrent operations exist.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum MergeClass {
    Lww,
    AppendLog,
    Manual,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FieldMetadata {
    pub path: String,
    pub merge: MergeClass,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct MergeRegistry {
    by_path: BTreeMap<String, MergeClass>,
}

impl MergeRegistry {
    pub fn new(metadata: impl IntoIterator<Item = FieldMetadata>) -> Result<Self, SyncError> {
        let mut by_path = BTreeMap::new();
        for entry in metadata {
            validate_path(&entry.path)?;
            if by_path.insert(entry.path.clone(), entry.merge).is_some() {
                return Err(SyncError::DuplicateMetadataPath(entry.path));
            }
        }
        Ok(Self { by_path })
    }

    pub fn merge_class(&self, path: &str) -> MergeClass {
        self.by_path
            .get(path)
            .copied()
            .unwrap_or(MergeClass::Manual)
    }

    pub fn is_registered(&self, path: &str) -> bool {
        self.by_path.contains_key(path)
    }
}

/// A single user intent. The flattened representation keeps fixtures compact:
/// `{"id":"a1","actor":"dev-a","lamport":1,"kind":"set-field", ...}`.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Operation {
    pub id: String,
    pub actor: String,
    pub lamport: u64,
    #[serde(flatten)]
    pub kind: OperationKind,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub enum OperationKind {
    SetField {
        path: String,
        value: Value,
    },
    AppendEntry {
        path: String,
        key: String,
        value: Value,
    },
}

impl Operation {
    pub fn set_field(id: String, actor: String, lamport: u64, path: String, value: Value) -> Self {
        Self {
            id,
            actor,
            lamport,
            kind: OperationKind::SetField { path, value },
        }
    }

    pub fn append_entry(
        id: String,
        actor: String,
        lamport: u64,
        path: String,
        key: String,
        value: Value,
    ) -> Self {
        Self {
            id,
            actor,
            lamport,
            kind: OperationKind::AppendEntry { path, key, value },
        }
    }

    pub fn validate(&self) -> Result<(), SyncError> {
        validate_bounded("operation id", &self.id, MAX_OPERATION_ID_BYTES)?;
        validate_bounded("actor", &self.actor, MAX_ACTOR_BYTES)?;
        if self.lamport == 0 {
            return Err(SyncError::ZeroLamport);
        }
        validate_path(self.path())?;
        if let OperationKind::AppendEntry { key, .. } = &self.kind {
            validate_bounded("append entry key", key, MAX_ENTRY_KEY_BYTES)?;
        }
        Ok(())
    }

    pub fn path(&self) -> &str {
        match &self.kind {
            OperationKind::SetField { path, .. } | OperationKind::AppendEntry { path, .. } => path,
        }
    }

    fn order_key(&self) -> (u64, &str, &str) {
        (self.lamport, self.actor.as_str(), self.id.as_str())
    }
}

/// A Lamport clock scoped to one actor. Callers must persist the counter with
/// their local log; observing remote timestamps keeps new local operations
/// ordered after everything already seen.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LamportClock {
    actor: String,
    counter: u64,
}

impl LamportClock {
    pub fn new(actor: impl Into<String>) -> Result<Self, SyncError> {
        let actor = actor.into();
        validate_bounded("actor", &actor, MAX_ACTOR_BYTES)?;
        Ok(Self { actor, counter: 0 })
    }

    pub fn actor(&self) -> &str {
        &self.actor
    }

    pub fn observe(&mut self, remote: u64) {
        self.counter = self.counter.max(remote);
    }

    pub fn tick(&mut self) -> Result<u64, SyncError> {
        self.counter = self
            .counter
            .checked_add(1)
            .ok_or(SyncError::ClockOverflow)?;
        Ok(self.counter)
    }

    pub fn set_field(
        &mut self,
        id: impl Into<String>,
        path: impl Into<String>,
        value: Value,
    ) -> Result<Operation, SyncError> {
        let operation = Operation::set_field(
            id.into(),
            self.actor.clone(),
            self.tick()?,
            path.into(),
            value,
        );
        operation.validate()?;
        Ok(operation)
    }

    pub fn append_entry(
        &mut self,
        id: impl Into<String>,
        path: impl Into<String>,
        key: impl Into<String>,
        value: Value,
    ) -> Result<Operation, SyncError> {
        let operation = Operation::append_entry(
            id.into(),
            self.actor.clone(),
            self.tick()?,
            path.into(),
            key.into(),
            value,
        );
        operation.validate()?;
        Ok(operation)
    }
}

/// A set of operations keyed by globally unique operation id.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct OperationLog {
    operations: BTreeMap<String, Operation>,
}

impl OperationLog {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn from_operations(
        operations: impl IntoIterator<Item = Operation>,
    ) -> Result<Self, SyncError> {
        let mut log = Self::new();
        for operation in operations {
            log.insert(operation)?;
        }
        Ok(log)
    }

    /// Insert one operation. Exact replays are idempotent; reusing an id for
    /// different content is rejected so conflicting histories cannot merge.
    pub fn insert(&mut self, operation: Operation) -> Result<bool, SyncError> {
        operation.validate()?;
        match self.operations.get(&operation.id) {
            Some(existing) if existing == &operation => Ok(false),
            Some(_) => Err(SyncError::ConflictingOperationId(operation.id)),
            None => {
                self.operations.insert(operation.id.clone(), operation);
                Ok(true)
            }
        }
    }

    /// Union another log into this one. The merge is commutative for valid
    /// logs because operation identity is global and projection is sorted.
    pub fn merge(&mut self, other: &Self) -> Result<usize, SyncError> {
        let mut pending = Vec::new();
        for operation in other.operations.values() {
            match self.operations.get(&operation.id) {
                Some(existing) if existing == operation => {}
                Some(_) => {
                    return Err(SyncError::ConflictingOperationId(operation.id.clone()));
                }
                None => pending.push(operation.clone()),
            }
        }
        let added = pending.len();
        for operation in pending {
            self.operations.insert(operation.id.clone(), operation);
        }
        Ok(added)
    }

    pub fn merged(&self, other: &Self) -> Result<Self, SyncError> {
        let mut merged = self.clone();
        merged.merge(other)?;
        Ok(merged)
    }

    pub fn contains(&self, id: &str) -> bool {
        self.operations.contains_key(id)
    }

    pub fn len(&self) -> usize {
        self.operations.len()
    }

    pub fn is_empty(&self) -> bool {
        self.operations.is_empty()
    }

    pub fn max_lamport(&self) -> u64 {
        self.operations
            .values()
            .map(|operation| operation.lamport)
            .max()
            .unwrap_or(0)
    }

    pub fn operations(&self) -> impl Iterator<Item = &Operation> {
        self.operations.values()
    }

    fn sorted(&self) -> Vec<&Operation> {
        let mut operations: Vec<_> = self.operations.values().collect();
        operations.sort_by(|left, right| left.order_key().cmp(&right.order_key()));
        operations
    }

    /// Apply the log in total `(lamport, actor, id)` order. This is the only
    /// projection order; merging logs in a different arrival order cannot
    /// change the result.
    pub fn project(&self, registry: &MergeRegistry) -> Result<Projection, SyncError> {
        let mut grouped: BTreeMap<&str, Vec<&Operation>> = BTreeMap::new();
        for operation in self.sorted() {
            grouped.entry(operation.path()).or_default().push(operation);
        }

        let mut projection = Projection::default();
        for (path, operations) in grouped {
            match registry.merge_class(path) {
                MergeClass::Lww => {
                    let last = require_set_field(path, &operations, MergeClass::Lww)?;
                    projection.fields.insert(path.to_owned(), last.clone());
                }
                MergeClass::Manual => {
                    let last = require_set_field(path, &operations, MergeClass::Manual)?;
                    let losers = operations
                        .iter()
                        .filter(|operation| operation_set_value(operation) != Some(last))
                        .map(|operation| operation.id.clone())
                        .collect::<Vec<_>>();
                    if !losers.is_empty() {
                        let winner = operations
                            .last()
                            .expect("non-empty operation group")
                            .id
                            .clone();
                        projection.conflicts.push(ProjectionConflict {
                            path: path.to_owned(),
                            merge: MergeClass::Manual,
                            reason: ConflictReason::ManualMultiWriter,
                            key: None,
                            winner,
                            losers,
                        });
                    }
                    projection.fields.insert(path.to_owned(), last.clone());
                }
                MergeClass::AppendLog => {
                    let mut by_key: BTreeMap<&str, Vec<&Operation>> = BTreeMap::new();
                    for operation in &operations {
                        let key = match &operation.kind {
                            OperationKind::AppendEntry { key, .. } => key.as_str(),
                            OperationKind::SetField { .. } => {
                                return Err(SyncError::MergeClassMismatch {
                                    path: path.to_owned(),
                                    merge: MergeClass::AppendLog,
                                });
                            }
                        };
                        by_key.entry(key).or_default().push(operation);
                    }

                    let mut entries = Vec::with_capacity(by_key.len());
                    for (key, operations) in by_key {
                        let winner = operations
                            .iter()
                            .copied()
                            .max_by(|left, right| {
                                canonical_json(
                                    operation_append_value(left)
                                        .expect("append group contains append operations"),
                                )
                                .cmp(&canonical_json(
                                    operation_append_value(right)
                                        .expect("append group contains append operations"),
                                ))
                                .then_with(|| left.order_key().cmp(&right.order_key()))
                            })
                            .expect("non-empty entry group");
                        let winner_value = operation_append_value(winner)
                            .expect("append group contains append operations");
                        let winner_canonical = canonical_json(winner_value);
                        let losers = operations
                            .iter()
                            .filter(|operation| {
                                canonical_json(
                                    operation_append_value(operation)
                                        .expect("append group contains append operations"),
                                ) != winner_canonical
                            })
                            .map(|operation| operation.id.clone())
                            .collect::<Vec<_>>();
                        if !losers.is_empty() {
                            projection.conflicts.push(ProjectionConflict {
                                path: path.to_owned(),
                                merge: MergeClass::AppendLog,
                                reason: ConflictReason::AppendKeyConflict,
                                key: Some(key.to_owned()),
                                winner: winner.id.clone(),
                                losers,
                            });
                        }
                        entries.push(json!({ "id": key, "value": winner_value }));
                    }
                    projection
                        .fields
                        .insert(path.to_owned(), Value::Array(entries));
                }
            }
        }
        Ok(projection)
    }
}

fn require_set_field<'a>(
    path: &str,
    operations: &'a [&Operation],
    merge: MergeClass,
) -> Result<&'a Value, SyncError> {
    let mut value = None;
    for operation in operations {
        match &operation.kind {
            OperationKind::SetField { value: next, .. } => value = Some(next),
            OperationKind::AppendEntry { .. } => {
                return Err(SyncError::MergeClassMismatch {
                    path: path.to_owned(),
                    merge,
                });
            }
        }
    }
    value.ok_or_else(|| SyncError::MergeClassMismatch {
        path: path.to_owned(),
        merge,
    })
}

fn operation_set_value(operation: &Operation) -> Option<&Value> {
    match &operation.kind {
        OperationKind::SetField { value, .. } => Some(value),
        OperationKind::AppendEntry { .. } => None,
    }
}

fn operation_append_value(operation: &Operation) -> Option<&Value> {
    match &operation.kind {
        OperationKind::AppendEntry { value, .. } => Some(value),
        OperationKind::SetField { .. } => None,
    }
}

fn canonical_json(value: &Value) -> String {
    serde_json::to_string(value).expect("JSON values always serialize")
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Projection {
    pub fields: BTreeMap<String, Value>,
    pub conflicts: Vec<ProjectionConflict>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ConflictReason {
    ManualMultiWriter,
    AppendKeyConflict,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProjectionConflict {
    pub path: String,
    pub merge: MergeClass,
    pub reason: ConflictReason,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub key: Option<String>,
    pub winner: String,
    pub losers: Vec<String>,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum SyncError {
    #[error("{field} is empty")]
    EmptyField { field: &'static str },
    #[error("{field} exceeds {limit} bytes")]
    OversizedField { field: &'static str, limit: usize },
    #[error("lamport timestamp must be at least 1")]
    ZeroLamport,
    #[error("lamport clock overflow")]
    ClockOverflow,
    #[error("duplicate field metadata path {0}")]
    DuplicateMetadataPath(String),
    #[error("operation id {0} is already used by different content")]
    ConflictingOperationId(String),
    #[error("field {path} uses {merge:?} but contains the wrong operation kind")]
    MergeClassMismatch { path: String, merge: MergeClass },
    #[error("invalid sync snapshot: {0}")]
    InvalidSnapshot(String),
    #[error("sync JSON serialization failed: {0}")]
    Serialization(String),
}

fn validate_bounded(field: &'static str, value: &str, limit: usize) -> Result<(), SyncError> {
    if value.trim().is_empty() {
        return Err(SyncError::EmptyField { field });
    }
    if value.len() > limit {
        return Err(SyncError::OversizedField { field, limit });
    }
    Ok(())
}

fn validate_path(path: &str) -> Result<(), SyncError> {
    validate_bounded("field path", path, MAX_PATH_BYTES)
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = include_str!("../../../protocol/fixtures/sync/operation-log-v1.json");

    #[derive(Deserialize)]
    struct Fixture {
        metadata: Vec<FieldMetadata>,
        logs: Vec<Vec<Operation>>,
        expected: Projection,
    }

    fn fixture() -> Fixture {
        serde_json::from_str(FIXTURE).expect("valid operation-log fixture")
    }

    fn fixture_logs(fixture: &Fixture) -> Vec<OperationLog> {
        fixture
            .logs
            .iter()
            .map(|operations| {
                OperationLog::from_operations(operations.clone()).expect("valid fixture log")
            })
            .collect()
    }

    #[test]
    fn operation_logs_merge_and_project_deterministically() {
        let fixture = fixture();
        let registry = MergeRegistry::new(fixture.metadata.clone()).expect("valid metadata");
        let logs = fixture_logs(&fixture);

        let mut forward = OperationLog::new();
        let mut reverse = OperationLog::new();
        for log in &logs {
            forward.merge(log).expect("forward merge");
        }
        for log in logs.iter().rev() {
            reverse.merge(log).expect("reverse merge");
        }

        assert_eq!(forward, reverse);
        assert_eq!(
            forward.project(&registry).expect("forward projection"),
            fixture.expected
        );
        assert_eq!(
            reverse.project(&registry).expect("reverse projection"),
            fixture.expected
        );

        let flattened = fixture
            .logs
            .iter()
            .flat_map(|operations| operations.iter().cloned())
            .collect::<Vec<_>>();
        let single = OperationLog::from_operations(flattened).expect("flattened log");
        assert_eq!(
            single.project(&registry).expect("flattened projection"),
            fixture.expected
        );
    }

    #[test]
    fn exact_replays_are_idempotent_and_conflicting_ids_are_rejected() {
        let operation = Operation::set_field(
            "op-1".to_owned(),
            "dev-a".to_owned(),
            1,
            "layout".to_owned(),
            json!({"x": 1}),
        );
        let mut log = OperationLog::from_operations([operation.clone()]).expect("valid log");
        assert!(!log.insert(operation.clone()).expect("replay"));
        assert_eq!(log.len(), 1);

        let conflicting = Operation::set_field(
            "op-1".to_owned(),
            "dev-b".to_owned(),
            2,
            "layout".to_owned(),
            json!({"x": 2}),
        );
        assert_eq!(
            log.insert(conflicting.clone()),
            Err(SyncError::ConflictingOperationId("op-1".to_owned()))
        );

        let other = OperationLog::from_operations([conflicting]).expect("separate log");
        assert_eq!(
            log.merge(&other),
            Err(SyncError::ConflictingOperationId("op-1".to_owned()))
        );
        assert_eq!(log.len(), 1);
    }

    #[test]
    fn lamport_clock_advances_and_observes_remote_timestamps() {
        let mut clock = LamportClock::new("dev-a").expect("valid actor");
        assert_eq!(clock.tick().expect("tick"), 1);
        clock.observe(9);
        assert_eq!(clock.tick().expect("tick"), 10);
        assert_eq!(clock.actor(), "dev-a");

        let operation = clock
            .append_entry("op-2", "instances", "win-1", json!({"id": "win-1"}))
            .expect("valid operation");
        assert_eq!(operation.lamport, 11);
        assert_eq!(operation.actor, "dev-a");
    }

    #[test]
    fn rejects_missing_values_and_invalid_metadata() {
        assert_eq!(
            Operation::set_field(
                "op-1".to_owned(),
                String::new(),
                1,
                "layout".to_owned(),
                Value::Null,
            )
            .validate(),
            Err(SyncError::EmptyField { field: "actor" })
        );
        assert_eq!(
            Operation::set_field(
                "op-1".to_owned(),
                "dev-a".to_owned(),
                0,
                "layout".to_owned(),
                Value::Null,
            )
            .validate(),
            Err(SyncError::ZeroLamport)
        );
        assert_eq!(
            MergeRegistry::new([
                FieldMetadata {
                    path: "layout".to_owned(),
                    merge: MergeClass::Lww,
                },
                FieldMetadata {
                    path: "layout".to_owned(),
                    merge: MergeClass::Manual,
                },
            ]),
            Err(SyncError::DuplicateMetadataPath("layout".to_owned()))
        );
    }

    #[test]
    fn append_conflicts_choose_the_maximum_canonical_value() {
        let registry = MergeRegistry::new([FieldMetadata {
            path: "items".to_owned(),
            merge: MergeClass::AppendLog,
        }])
        .expect("valid registry");
        let log = OperationLog::from_operations([
            Operation::append_entry(
                "op-a".to_owned(),
                "dev-a".to_owned(),
                1,
                "items".to_owned(),
                "k".to_owned(),
                json!("z"),
            ),
            Operation::append_entry(
                "op-b".to_owned(),
                "dev-b".to_owned(),
                2,
                "items".to_owned(),
                "k".to_owned(),
                json!("a"),
            ),
        ])
        .expect("valid log");

        let projection = log.project(&registry).expect("valid projection");
        assert_eq!(
            projection.fields.get("items"),
            Some(&json!([{ "id": "k", "value": "z" }]))
        );
        assert_eq!(
            projection.conflicts,
            vec![ProjectionConflict {
                path: "items".to_owned(),
                merge: MergeClass::AppendLog,
                reason: ConflictReason::AppendKeyConflict,
                key: Some("k".to_owned()),
                winner: "op-a".to_owned(),
                losers: vec!["op-b".to_owned()],
            }]
        );
    }

    #[test]
    fn rejects_operation_kinds_that_do_not_match_the_merge_class() {
        let registry = MergeRegistry::new([FieldMetadata {
            path: "instances".to_owned(),
            merge: MergeClass::AppendLog,
        }])
        .expect("valid registry");
        let log = OperationLog::from_operations([Operation::set_field(
            "op-1".to_owned(),
            "dev-a".to_owned(),
            1,
            "instances".to_owned(),
            json!([]),
        )])
        .expect("valid log");

        assert_eq!(
            log.project(&registry),
            Err(SyncError::MergeClassMismatch {
                path: "instances".to_owned(),
                merge: MergeClass::AppendLog,
            })
        );
    }
}
