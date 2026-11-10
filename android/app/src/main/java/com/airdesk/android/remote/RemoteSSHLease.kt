package com.airdesk.android.remote

enum class RemoteSSHOperation(val wire: String) {
    CONNECT("connect"),
    WRITE("write"),
    RESIZE("resize"),
}

data class RemoteSSHLease(
    val leaseId: String,
    val capUri: String = RemoteSSHLeaseRegistry.CAPABILITY_URI,
    val workspaceId: String,
    val applicationId: String,
    val requesterDeviceId: String,
    val sessionId: String,
    val issuedAtEpochMillis: Long,
    val expiresAtEpochMillis: Long? = null,
    val revoked: Boolean = false,
    val revocationReason: String? = null,
    val operations: Set<RemoteSSHOperation> = RemoteSSHOperation.entries.toSet(),
    val auditId: String,
)

data class RemoteSSHContext(
    val capUri: String = RemoteSSHLeaseRegistry.CAPABILITY_URI,
    val workspaceId: String,
    val applicationId: String,
    val requesterDeviceId: String,
    val sessionId: String,
    val leaseId: String? = null,
)

data class RemoteSSHLeaseRequest(
    val leaseId: String?,
    val capUri: String,
    val workspaceId: String,
    val applicationId: String,
    val requesterDeviceId: String,
    val sessionId: String,
    val operation: RemoteSSHOperation,
) {
    constructor(
        context: RemoteSSHContext,
        operation: RemoteSSHOperation,
    ) : this(
        leaseId = context.leaseId,
        capUri = context.capUri,
        workspaceId = context.workspaceId,
        applicationId = context.applicationId,
        requesterDeviceId = context.requesterDeviceId,
        sessionId = context.sessionId,
        operation = operation,
    )
}

enum class RemoteSSHAuditDecision(val wire: String) {
    ALLOWED("allowed"),
    DENIED("denied"),
    REVOKED("revoked"),
    EXPIRED("expired"),
    BUSY("busy"),
}

data class RemoteSSHAuditEvent(
    val timestampEpochMillis: Long,
    val leaseId: String?,
    val auditId: String?,
    val capUri: String,
    val workspaceId: String,
    val sessionId: String,
    val operation: RemoteSSHOperation,
    val decision: RemoteSSHAuditDecision,
    val reason: String?,
)

class RemoteSSHLeaseRegistry(
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val leases = LinkedHashMap<String, RemoteSSHLease>()
    private val activeOwners = LinkedHashMap<String, String>()

    @Synchronized
    fun grant(lease: RemoteSSHLease): RemoteSSHLease {
        validate(lease)
        leases[lease.leaseId] = lease
        return lease
    }

    @Synchronized
    fun revoke(leaseId: String, reason: String = "Revoked"): Boolean {
        val current = leases[leaseId] ?: return false
        leases[leaseId] = current.copy(revoked = true, revocationReason = reason)
        activeOwners.remove(leaseId)
        return true
    }

    @Synchronized
    fun remove(leaseId: String): Boolean {
        activeOwners.remove(leaseId)
        return leases.remove(leaseId) != null
    }

    @Synchronized
    fun lease(leaseId: String): RemoteSSHLease? = leases[leaseId]

    @Synchronized
    fun authorize(
        request: RemoteSSHLeaseRequest,
        owner: String,
    ): RemoteSSHLease {
        val leaseId = request.leaseId
        if (leaseId.isNullOrEmpty()) {
            throw leaseFailure(RemoteSSHErrorCode.LEASE_DENIED, "LeaseDenied: no matching capability lease authorizes this operation.")
        }
        val lease = leases[leaseId]
            ?: throw leaseFailure(RemoteSSHErrorCode.LEASE_DENIED, "LeaseDenied: no matching capability lease authorizes this operation.")
        if (lease.revoked) {
            throw leaseFailure(RemoteSSHErrorCode.LEASE_REVOKED, "LeaseRevoked: the capability lease was revoked.")
        }
        lease.expiresAtEpochMillis?.let { expiresAt ->
            if (expiresAt <= now()) {
                throw leaseFailure(RemoteSSHErrorCode.LEASE_EXPIRED, "LeaseExpired: the capability lease has expired.")
            }
        }
        if (lease.capUri != request.capUri ||
            lease.workspaceId != request.workspaceId ||
            lease.applicationId != request.applicationId ||
            lease.requesterDeviceId != request.requesterDeviceId ||
            (lease.sessionId.isNotEmpty() && lease.sessionId != request.sessionId) ||
            !lease.operations.contains(request.operation)
        ) {
            throw leaseFailure(RemoteSSHErrorCode.LEASE_DENIED, "LeaseDenied: no matching capability lease authorizes this operation.")
        }
        val activeOwner = activeOwners[leaseId]
        if (activeOwner != null && activeOwner != owner) {
            throw leaseFailure(RemoteSSHErrorCode.LEASE_BUSY, "LeaseBusy: the capability lease is already in use by another terminal.")
        }
        if (request.operation == RemoteSSHOperation.CONNECT) {
            activeOwners[leaseId] = owner
        } else if (activeOwners[leaseId] != owner) {
            throw leaseFailure(RemoteSSHErrorCode.LEASE_DENIED, "LeaseDenied: no matching capability lease authorizes this operation.")
        }
        return lease
    }

    @Synchronized
    fun release(leaseId: String, owner: String) {
        if (activeOwners[leaseId] == owner) {
            activeOwners.remove(leaseId)
        }
    }

    @Synchronized
    fun isActive(leaseId: String, owner: String): Boolean =
        activeOwners[leaseId] == owner

    private fun validate(lease: RemoteSSHLease) {
        if (!valid(lease.leaseId, 128)) throw invalid("lease id")
        if (!valid(lease.capUri, 256) || !lease.capUri.startsWith("airdesk://")) {
            throw invalid("capability URI")
        }
        if (!valid(lease.workspaceId, 128)) throw invalid("workspace id")
        if (!valid(lease.applicationId, 128)) throw invalid("application id")
        if (!valid(lease.requesterDeviceId, 128)) throw invalid("requester device id")
        if (lease.sessionId.length > 128 || lease.sessionId.contains('\u0000')) {
            throw invalid("session id")
        }
        if (!valid(lease.auditId, 128)) throw invalid("audit id")
        if (lease.operations.isEmpty()) throw invalid("operations")
        lease.revocationReason?.let {
            if (it.length > 256) throw invalid("revocation reason")
        }
        if (lease.issuedAtEpochMillis < 0 ||
            (lease.expiresAtEpochMillis != null && lease.expiresAtEpochMillis < lease.issuedAtEpochMillis)
        ) {
            throw invalid("lease timestamps")
        }
    }

    private fun valid(value: String, maximum: Int): Boolean =
        value.isNotEmpty() && value.length <= maximum && !value.contains('\u0000')

    private fun invalid(field: String): RemoteSSHException =
        leaseFailure(RemoteSSHErrorCode.LEASE_INVALID, "InvalidLease: invalid $field.")

    private fun leaseFailure(code: RemoteSSHErrorCode, message: String): RemoteSSHException =
        RemoteSSHException(code, message)

    companion object {
        const val CAPABILITY_URI = "airdesk://pty/spawn"
    }
}
