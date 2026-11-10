package com.airdesk.android.remote

import java.util.UUID

class RemoteSSHTerminal(
    private val driver: RemoteSSHDriver,
    private val leases: RemoteSSHLeaseRegistry,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val lock = Any()
    private val owner = UUID.randomUUID().toString()
    private val auditLog = ArrayDeque<RemoteSSHAuditEvent>()
    private var activeLeaseId: String? = null
    private var context: RemoteSSHContext? = null

    var onAudit: ((RemoteSSHAuditEvent) -> Unit)? = null
    var onEvent: ((RemoteSSHEvent) -> Unit)? = null

    val auditEvents: List<RemoteSSHAuditEvent>
        get() = synchronized(lock) { auditLog.toList() }

    val isRunning: Boolean
        get() = synchronized(lock) {
            activeLeaseId != null && driver.isRunning
        }

    fun grantLease(lease: RemoteSSHLease): RemoteSSHLease = leases.grant(lease)

    fun revokeLease(leaseId: String, reason: String = "Revoked"): Boolean =
        leases.revoke(leaseId, reason)

    fun lease(leaseId: String): RemoteSSHLease? = leases.lease(leaseId)

    init {
        driver.onEvent = { event -> handle(event) }
    }

    fun start(
        configuration: RemoteSSHConfiguration,
        size: RemoteSSHSize,
        context: RemoteSSHContext,
    ) {
        stop()
        val normalizedContext = if (context.capUri.isEmpty()) {
            context.copy(capUri = CAPABILITY_URI)
        } else {
            context
        }
        val request = RemoteSSHLeaseRequest(normalizedContext, RemoteSSHOperation.CONNECT)
        val lease = try {
            authorize(request, auditSuccess = true)
        } catch (error: RemoteSSHException) {
            throw error
        }
        synchronized(lock) {
            activeLeaseId = lease.leaseId
            this.context = normalizedContext
        }

        try {
            driver.start(configuration, size)
        } catch (error: Throwable) {
            releaseActiveLease()
            synchronized(lock) {
                this.context = null
            }
            throw error
        }
    }

    fun write(data: ByteArray) {
        if (data.isEmpty()) return
        val currentContext = synchronized(lock) {
            if (!isRunning || context == null || activeLeaseId == null) return
            context
        } ?: return
        val leaseId = synchronized(lock) { activeLeaseId } ?: return
        val request = RemoteSSHLeaseRequest(
            currentContext.copy(leaseId = leaseId),
            RemoteSSHOperation.WRITE,
        )
        try {
            authorize(request, auditSuccess = false)
            driver.write(data)
        } catch (error: RemoteSSHException) {
            fail(error)
        }
    }

    fun resize(columns: Int, rows: Int) {
        val currentContext = synchronized(lock) {
            if (!isRunning || context == null || activeLeaseId == null) return
            context
        } ?: return
        val leaseId = synchronized(lock) { activeLeaseId } ?: return
        val request = RemoteSSHLeaseRequest(
            currentContext.copy(leaseId = leaseId),
            RemoteSSHOperation.RESIZE,
        )
        try {
            authorize(request, auditSuccess = false)
            driver.resize(columns, rows)
        } catch (error: RemoteSSHException) {
            fail(error)
        }
    }

    fun stop() {
        val shouldStop = synchronized(lock) {
            driver.isRunning || activeLeaseId != null
        }
        if (shouldStop) {
            driver.stop()
        }
        releaseActiveLease()
        synchronized(lock) {
            context = null
        }
    }

    fun shutdown() {
        stop()
        driver.shutdown()
    }

    private fun authorize(
        request: RemoteSSHLeaseRequest,
        auditSuccess: Boolean,
    ): RemoteSSHLease {
        return try {
            val lease = leases.authorize(request, owner)
            if (auditSuccess) {
                record(
                    request = request,
                    lease = lease,
                    decision = RemoteSSHAuditDecision.ALLOWED,
                    reason = null,
                )
            }
            lease
        } catch (error: RemoteSSHException) {
            val lease = request.leaseId?.let { leases.lease(it) }
            record(
                request = request,
                lease = lease,
                decision = decisionFor(error.code),
                reason = error.message,
            )
            throw error
        }
    }

    private fun fail(error: RemoteSSHException) {
        driver.stop()
        releaseActiveLease()
        synchronized(lock) {
            context = null
        }
        onEvent?.invoke(RemoteSSHEvent.Exit(error.message))
    }

    private fun handle(event: RemoteSSHEvent) {
        if (event is RemoteSSHEvent.Exit) {
            releaseActiveLease()
            synchronized(lock) {
                context = null
            }
        }
        onEvent?.invoke(event)
    }

    private fun releaseActiveLease() {
        val leaseId = synchronized(lock) {
            val current = activeLeaseId
            activeLeaseId = null
            current
        }
        if (leaseId != null) {
            leases.release(leaseId, owner)
        }
    }

    private fun record(
        request: RemoteSSHLeaseRequest,
        lease: RemoteSSHLease?,
        decision: RemoteSSHAuditDecision,
        reason: String?,
    ) {
        val event = RemoteSSHAuditEvent(
            timestampEpochMillis = now(),
            leaseId = request.leaseId,
            auditId = lease?.auditId,
            capUri = request.capUri,
            workspaceId = request.workspaceId,
            sessionId = request.sessionId,
            operation = request.operation,
            decision = decision,
            reason = reason,
        )
        synchronized(lock) {
            auditLog.addLast(event)
            while (auditLog.size > MAXIMUM_AUDIT_EVENTS) {
                auditLog.removeFirst()
            }
        }
        onAudit?.invoke(event)
    }

    private fun decisionFor(code: RemoteSSHErrorCode): RemoteSSHAuditDecision {
        return when (code) {
            RemoteSSHErrorCode.LEASE_REVOKED -> RemoteSSHAuditDecision.REVOKED
            RemoteSSHErrorCode.LEASE_EXPIRED -> RemoteSSHAuditDecision.EXPIRED
            RemoteSSHErrorCode.LEASE_BUSY -> RemoteSSHAuditDecision.BUSY
            else -> RemoteSSHAuditDecision.DENIED
        }
    }

    companion object {
        const val CAPABILITY_URI = "airdesk://pty/spawn"
        const val MAXIMUM_AUDIT_EVENTS = 256
    }
}
