package com.airdesk.android.input

enum class InputLeaseErrorCode {
    LEASE_DENIED,
    LEASE_REVOKED,
    LEASE_EXPIRED,
    LEASE_BUSY,
    LEASE_INVALID,
}

class InputLeaseException(
    val code: InputLeaseErrorCode,
    override val message: String,
) : Exception(message)

data class InputLease(
    val leaseId: String,
    val controllerDeviceId: String,
    val workspaceId: String,
    val applicationId: String,
    val sessionId: String,
    val epochLow: Int,
    val issuedAtEpochMillis: Long,
    val expiresAtEpochMillis: Long? = null,
    val revoked: Boolean = false,
    val revocationReason: String? = null,
    val auditId: String,
    val capUri: String = CAPABILITY_URI,
) {
    companion object {
        const val CAPABILITY_URI = "airdesk://input/pointer"
    }
}

class InputLeaseRegistry(
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val leases = LinkedHashMap<String, InputLease>()
    private var activeLeaseId: String? = null
    private var activeOwner: String? = null

    @Synchronized
    fun grant(lease: InputLease): InputLease {
        validate(lease)
        val existing = leases[lease.leaseId]
        if (existing != null && existing.revoked.not()) {
            throw invalid("lease id is already active")
        }
        leases[lease.leaseId] = lease
        return lease
    }

    @Synchronized
    fun revoke(leaseId: String, reason: String = "Revoked"): Boolean {
        val lease = leases[leaseId] ?: return false
        leases[leaseId] = lease.copy(revoked = true, revocationReason = reason.take(256))
        if (activeLeaseId == leaseId) {
            activeLeaseId = null
            activeOwner = null
        }
        return true
    }

    @Synchronized
    fun remove(leaseId: String): Boolean {
        if (activeLeaseId == leaseId) {
            activeLeaseId = null
            activeOwner = null
        }
        return leases.remove(leaseId) != null
    }

    @Synchronized
    fun lease(leaseId: String): InputLease? = leases[leaseId]

    @Synchronized
    fun activeOwner(): String? = activeOwner

    @Synchronized
    fun authorize(
        leaseId: String?,
        owner: String,
        epochLow: Int,
    ): InputLease {
        if (leaseId.isNullOrEmpty()) {
            throw denied("no matching input lease")
        }
        val lease = leases[leaseId] ?: throw denied("no matching input lease")
        if (lease.controllerDeviceId != owner) {
            throw denied("lease belongs to another controller")
        }
        if (lease.revoked) {
            throw InputLeaseException(
                InputLeaseErrorCode.LEASE_REVOKED,
                "LeaseRevoked: the input lease was revoked.",
            )
        }
        lease.expiresAtEpochMillis?.let { expiresAt ->
            if (expiresAt <= now()) {
                throw InputLeaseException(
                    InputLeaseErrorCode.LEASE_EXPIRED,
                    "LeaseExpired: the input lease has expired.",
                )
            }
        }
        if (epochLow != lease.epochLow) {
            throw denied("input lease epoch does not match")
        }
        val currentOwner = activeOwner
        if (currentOwner != null && currentOwner != owner) {
            throw InputLeaseException(
                InputLeaseErrorCode.LEASE_BUSY,
                "LeaseBusy: another controller owns the input surface.",
            )
        }
        if (activeLeaseId != null && activeLeaseId != leaseId) {
            throw InputLeaseException(
                InputLeaseErrorCode.LEASE_BUSY,
                "LeaseBusy: another input lease is active.",
            )
        }
        activeLeaseId = leaseId
        activeOwner = owner
        return lease
    }

    @Synchronized
    fun validateActive(leaseId: String, owner: String): InputLease {
        if (activeLeaseId != leaseId || activeOwner != owner) {
            throw denied("input lease is not active")
        }
        val lease = leases[leaseId] ?: throw denied("input lease is not active")
        if (lease.revoked) {
            throw InputLeaseException(
                InputLeaseErrorCode.LEASE_REVOKED,
                "LeaseRevoked: the input lease was revoked.",
            )
        }
        lease.expiresAtEpochMillis?.let { expiresAt ->
            if (expiresAt <= now()) {
                throw InputLeaseException(
                    InputLeaseErrorCode.LEASE_EXPIRED,
                    "LeaseExpired: the input lease has expired.",
                )
            }
        }
        return lease
    }

    @Synchronized
    fun release(leaseId: String, owner: String) {
        if (activeLeaseId == leaseId && activeOwner == owner) {
            activeLeaseId = null
            activeOwner = null
        }
    }

    @Synchronized
    fun isActive(leaseId: String, owner: String): Boolean =
        activeLeaseId == leaseId && activeOwner == owner

    private fun validate(lease: InputLease) {
        if (!valid(lease.leaseId, 128)) throw invalid("lease id")
        if (!valid(lease.controllerDeviceId, 128)) throw invalid("controller device id")
        if (!valid(lease.workspaceId, 128)) throw invalid("workspace id")
        if (!valid(lease.applicationId, 128)) throw invalid("application id")
        if (lease.sessionId.length > 128 || lease.sessionId.contains('\u0000')) {
            throw invalid("session id")
        }
        if (!valid(lease.auditId, 128)) throw invalid("audit id")
        if (lease.epochLow !in 0..0xffff) throw invalid("epoch")
        if (!lease.capUri.startsWith("airdesk://") || lease.capUri.length > 256) {
            throw invalid("capability URI")
        }
        if (lease.issuedAtEpochMillis < 0 ||
            (lease.expiresAtEpochMillis != null &&
                lease.expiresAtEpochMillis < lease.issuedAtEpochMillis)
        ) {
            throw invalid("lease timestamps")
        }
        lease.revocationReason?.let {
            if (it.length > 256) throw invalid("revocation reason")
        }
    }

    private fun valid(value: String, maximum: Int): Boolean =
        value.isNotEmpty() && value.length <= maximum && !value.contains('\u0000')

    private fun invalid(field: String): InputLeaseException =
        InputLeaseException(InputLeaseErrorCode.LEASE_INVALID, "InvalidLease: invalid $field.")

    private fun denied(reason: String): InputLeaseException =
        InputLeaseException(InputLeaseErrorCode.LEASE_DENIED, "LeaseDenied: $reason.")
}
