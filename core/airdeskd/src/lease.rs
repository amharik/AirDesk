use std::collections::{BTreeSet, HashMap};
use std::fmt;

pub const CAPABILITY_URI: &str = "airdesk://pty/spawn";
pub const MAX_LEASE_BYTES: usize = 128;
pub const MAX_URI_BYTES: usize = 256;
pub const MAX_OPERATIONS: usize = 16;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TerminalLease {
    pub lease_id: String,
    pub cap_uri: String,
    pub workspace_id: String,
    pub application_id: String,
    pub requester_device_id: String,
    pub session_id: String,
    pub operations: BTreeSet<String>,
    pub expires_at_ms: u64,
    pub revoked: bool,
}

impl TerminalLease {
    pub fn new(
        lease_id: impl Into<String>,
        workspace_id: impl Into<String>,
        application_id: impl Into<String>,
        requester_device_id: impl Into<String>,
        session_id: impl Into<String>,
        operations: impl IntoIterator<Item = impl Into<String>>,
    ) -> Result<Self, LeaseError> {
        let lease = Self {
            lease_id: lease_id.into(),
            cap_uri: CAPABILITY_URI.to_string(),
            workspace_id: workspace_id.into(),
            application_id: application_id.into(),
            requester_device_id: requester_device_id.into(),
            session_id: session_id.into(),
            operations: operations.into_iter().map(Into::into).collect(),
            expires_at_ms: 0,
            revoked: false,
        };
        lease.validate()?;
        Ok(lease)
    }

    fn validate(&self) -> Result<(), LeaseError> {
        validate_text(&self.lease_id, MAX_LEASE_BYTES, "lease id")?;
        if !self.cap_uri.starts_with("airdesk://") || self.cap_uri.len() > MAX_URI_BYTES {
            return Err(LeaseError::Invalid("capability URI"));
        }
        validate_text(&self.workspace_id, MAX_LEASE_BYTES, "workspace id")?;
        validate_text(&self.application_id, MAX_LEASE_BYTES, "application id")?;
        validate_text(
            &self.requester_device_id,
            MAX_LEASE_BYTES,
            "requester device id",
        )?;
        if self.session_id.len() > MAX_LEASE_BYTES {
            return Err(LeaseError::Invalid("session id"));
        }
        if self.operations.is_empty() || self.operations.len() > MAX_OPERATIONS {
            return Err(LeaseError::Invalid("operations"));
        }
        for operation in &self.operations {
            validate_text(operation, 32, "operation")?;
        }
        Ok(())
    }

    pub fn authorize(
        &self,
        operation: &str,
        session_id: &str,
        now_ms: u64,
    ) -> Result<(), LeaseError> {
        if self.revoked {
            return Err(LeaseError::Revoked);
        }
        if self.expires_at_ms != 0 && self.expires_at_ms <= now_ms {
            return Err(LeaseError::Expired);
        }
        if self.cap_uri != CAPABILITY_URI {
            return Err(LeaseError::Scope);
        }
        if !self.session_id.is_empty() && self.session_id != session_id {
            return Err(LeaseError::Scope);
        }
        if !self.operations.contains(operation) {
            return Err(LeaseError::Operation(operation.to_string()));
        }
        Ok(())
    }
}

fn validate_text(value: &str, maximum: usize, field: &'static str) -> Result<(), LeaseError> {
    if value.is_empty() || value.len() > maximum || value.contains('\0') {
        return Err(LeaseError::Invalid(field));
    }
    Ok(())
}

#[derive(Debug, Clone, Default)]
pub struct LeaseRegistry {
    leases: HashMap<String, TerminalLease>,
}

impl LeaseRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn grant(&mut self, lease: TerminalLease) -> Result<(), LeaseError> {
        lease.validate()?;
        self.leases.insert(lease.lease_id.clone(), lease);
        Ok(())
    }

    pub fn revoke(&mut self, lease_id: &str, reason: &str) -> Result<(), LeaseError> {
        let lease = self.leases.get_mut(lease_id).ok_or(LeaseError::Unknown)?;
        lease.revoked = true;
        if reason.len() > 256 {
            return Err(LeaseError::Invalid("revocation reason"));
        }
        Ok(())
    }

    pub fn remove(&mut self, lease_id: &str) -> Option<TerminalLease> {
        self.leases.remove(lease_id)
    }

    pub fn authorize(
        &self,
        lease_id: Option<&str>,
        operation: &str,
        session_id: &str,
        now_ms: u64,
    ) -> Result<&TerminalLease, LeaseError> {
        let lease_id = lease_id
            .filter(|value| !value.is_empty())
            .ok_or(LeaseError::Missing)?;
        let lease = self.leases.get(lease_id).ok_or(LeaseError::Unknown)?;
        lease.authorize(operation, session_id, now_ms)?;
        Ok(lease)
    }

    pub fn from_records(text: &str) -> Result<Self, LeaseError> {
        let mut registry = Self::new();
        for (index, line) in text.lines().enumerate() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let mut fields = HashMap::new();
            for part in line.split_whitespace() {
                let (key, value) = part.split_once('=').ok_or(LeaseError::Parse(index + 1))?;
                fields.insert(key, value);
            }
            let required = |key: &str| {
                fields
                    .get(key)
                    .copied()
                    .filter(|value| !value.is_empty())
                    .ok_or(LeaseError::Parse(index + 1))
            };
            let operations = required("operations")?
                .split(',')
                .filter(|value| !value.is_empty())
                .collect::<Vec<_>>();
            let expires_at_ms = required("expires_at")?
                .parse::<u64>()
                .map_err(|_| LeaseError::Parse(index + 1))?;
            let revoked = fields
                .get("revoked")
                .map(|value| matches!(*value, "1" | "true"))
                .unwrap_or(false);
            let mut lease = TerminalLease::new(
                required("id")?,
                required("workspace")?,
                required("application")?,
                required("requester")?,
                required("session")?,
                operations,
            )?;
            lease.cap_uri = fields
                .get("cap_uri")
                .copied()
                .unwrap_or(CAPABILITY_URI)
                .to_string();
            lease.expires_at_ms = expires_at_ms;
            lease.revoked = revoked;
            registry.grant(lease)?;
        }
        Ok(registry)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LeaseError {
    Missing,
    Unknown,
    Revoked,
    Expired,
    Scope,
    Operation(String),
    Invalid(&'static str),
    Parse(usize),
}

impl fmt::Display for LeaseError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Missing => write!(formatter, "LeaseDenied: a lease id is required"),
            Self::Unknown => write!(formatter, "LeaseDenied: the lease is not provisioned"),
            Self::Revoked => write!(formatter, "LeaseRevoked: the lease was revoked"),
            Self::Expired => write!(formatter, "LeaseExpired: the lease expired"),
            Self::Scope => write!(formatter, "LeaseDenied: the lease scope does not match"),
            Self::Operation(operation) => write!(
                formatter,
                "LeaseDenied: operation {operation} is not leased"
            ),
            Self::Invalid(field) => write!(formatter, "InvalidLease: {field}"),
            Self::Parse(line) => write!(formatter, "InvalidLease: parse error on line {line}"),
        }
    }
}

impl std::error::Error for LeaseError {}
