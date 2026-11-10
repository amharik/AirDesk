package com.airdesk.android.agent

import com.airdesk.android.capabilities.Authorization
import com.airdesk.android.capabilities.Availability

enum class DeviceAgentLifecycleState(val wire: String) {
    STARTING("starting"),
    READY("ready"),
    DEGRADED("degraded"),
    UNAVAILABLE("unavailable"),
}

enum class DeviceAgentEventType(val wire: String) {
    LIFECYCLE("lifecycle"),
    HEALTH("health"),
    CAPABILITY("capability"),
    LEASE("lease"),
    ;

    companion object {
        fun fromWire(value: String): DeviceAgentEventType? =
            entries.firstOrNull { it.wire == value }
    }
}

enum class DeviceAgentPlatformPermissionState(val wire: String) {
    GRANTED("granted"),
    DENIED("denied"),
    NOT_DETERMINED("not-determined"),
    RESTRICTED("restricted"),
}

enum class DeviceAgentErrorCode(val wire: String) {
    INVALID_IDENTITY("invalid-identity"),
    INVALID_CAPABILITY("invalid-capability"),
    CAPABILITY_UNKNOWN("capability-unknown"),
    AUTHORIZATION_DENIED("authorization-denied"),
    AUTHORIZATION_REVOKED("authorization-revoked"),
    CAPABILITY_BUSY("capability-busy"),
    CAPABILITY_RESTRICTED("capability-restricted"),
    CAPABILITY_UNAVAILABLE("capability-unavailable"),
    OPERATION_NOT_ALLOWED("operation-not-allowed"),
    PLATFORM_PERMISSION_DENIED("platform-permission-denied"),
    AGENT_UNAVAILABLE("agent-unavailable"),
    LEASE_NOT_FOUND("lease-not-found"),
    INVALID_EVENT_TYPE("invalid-event-type"),
    INVALID_REQUEST("invalid-request"),
}

class DeviceAgentException(
    val code: DeviceAgentErrorCode,
    message: String,
    val detail: String? = null,
) : IllegalStateException(message)

data class DeviceAgentIdentity(
    val deviceId: String,
    val displayName: String,
    val platform: String,
    val algorithm: String,
    val publicKeySpkiBase64Url: String,
    val createdAtEpochMillis: Long,
)

data class DeviceAgentCapability(
    val capUri: String,
    val version: Int,
    val providerDeviceId: String,
    val operations: List<String>,
    val permissions: List<String>,
    val execution: String,
    val transport: String,
    val constraints: String,
    val availability: Availability,
    val authorization: Authorization,
    val label: String,
    val summary: String,
    val note: String,
    val authorizationRef: String? = null,
)

data class DeviceAgentCapabilityRequest(
    val capUri: String,
    val operations: List<String>,
    val workspaceId: String,
    val applicationId: String,
    val requesterDeviceId: String,
    val sessionId: String,
    val leaseId: String? = null,
    val auditId: String? = null,
)

data class DeviceAgentLease(
    val leaseId: String,
    val auditId: String,
    val capUri: String,
    val operations: List<String>,
    val workspaceId: String,
    val applicationId: String,
    val requesterDeviceId: String,
    val sessionId: String,
    val issuedAtEpochMillis: Long,
    val expiresAtEpochMillis: Long,
)

data class DeviceAgentHealth(
    val state: DeviceAgentLifecycleState,
    val generation: Long,
    val uptimeMillis: Long,
    val capabilityCount: Int,
    val availableCapabilityCount: Int,
    val busyCapabilityCount: Int,
    val restrictedCapabilityCount: Int,
    val unavailableCapabilityCount: Int,
    val authorizedCapabilityCount: Int,
    val activeLeaseCount: Int,
)

data class DeviceAgentEvent(
    val type: DeviceAgentEventType,
    val sequence: Long,
    val atEpochMillis: Long,
    val action: String,
    val leaseId: String? = null,
    val capUri: String? = null,
    val state: DeviceAgentLifecycleState? = null,
    val permission: String? = null,
)

class DeviceAgentSubscription internal constructor(
    private val onCancel: () -> Unit,
) {
    var active: Boolean = true
        private set

    fun cancel() {
        if (!active) return
        active = false
        onCancel()
    }
}

class DeviceAgent(
    identity: DeviceAgentIdentity,
    capabilities: List<DeviceAgentCapability>,
    permissions: Map<String, DeviceAgentPlatformPermissionState> = emptyMap(),
    private val leaseDurationMillis: Long = 600_000,
    private val now: () -> Long = { System.currentTimeMillis() },
) {
    private data class Subscription(
        val type: DeviceAgentEventType,
        val handler: (DeviceAgentEvent) -> Unit,
    )

    private val identityValue = identity
    private val capabilityValues = capabilities.toList()
    private val permissionStates = permissions.toMap()
    private val leases = LinkedHashMap<String, DeviceAgentLease>()
    private val subscriptions = LinkedHashMap<Long, Subscription>()
    private var lifecycleState = DeviceAgentLifecycleState.STARTING
    private var generation = 0L
    private var startedAtEpochMillis: Long? = null
    private var nextSubscriptionId = 0L
    private var nextSequence = 0L
    private var nextLeaseOrdinal = 0L

    init {
        if (!bounded(identityValue.deviceId, 512) ||
            !bounded(identityValue.displayName, 128) ||
            !bounded(identityValue.platform, 32) ||
            !bounded(identityValue.algorithm, 32) ||
            !bounded(identityValue.publicKeySpkiBase64Url, 4096) ||
            identityValue.createdAtEpochMillis < 0
        ) {
            throw failure(
                DeviceAgentErrorCode.INVALID_IDENTITY,
                "the device agent identity is invalid",
            )
        }
        if (leaseDurationMillis <= 0) {
            throw failure(
                DeviceAgentErrorCode.INVALID_REQUEST,
                "lease duration must be positive",
            )
        }
        if (capabilityValues.isEmpty() ||
            capabilityValues.map { it.capUri }.toSet().size != capabilityValues.size
        ) {
            throw failure(
                DeviceAgentErrorCode.INVALID_CAPABILITY,
                "capabilities must have unique URIs",
            )
        }
        capabilityValues.forEach { capability ->
            if (!bounded(capability.capUri, 512) ||
                capability.version < 1 ||
                !bounded(capability.providerDeviceId, 512) ||
                capability.operations.isEmpty() ||
                capability.operations.toSet().size != capability.operations.size ||
                capability.operations.any { !bounded(it, 128) } ||
                capability.permissions.toSet().size != capability.permissions.size ||
                !bounded(capability.execution, 64) ||
                !bounded(capability.transport, 64) ||
                !bounded(capability.constraints, 4096) ||
                !bounded(capability.label, 128) ||
                !bounded(capability.summary, 512) ||
                !bounded(capability.note, 2048) ||
                capability.authorizationRef?.let { !bounded(it, 256) } == true
            ) {
                throw failure(
                    DeviceAgentErrorCode.INVALID_CAPABILITY,
                    "invalid capability ${capability.capUri}",
                    capability.capUri,
                )
            }
        }
    }

    val state: DeviceAgentLifecycleState
        get() = lifecycleState

    fun identity(): DeviceAgentIdentity = identityValue

    fun capabilities(): List<DeviceAgentCapability> =
        capabilityValues.sortedBy { it.capUri }

    fun start() {
        if (lifecycleState == DeviceAgentLifecycleState.READY) return
        val action = if (lifecycleState == DeviceAgentLifecycleState.UNAVAILABLE) {
            "reconnected"
        } else {
            "started"
        }
        lifecycleState = DeviceAgentLifecycleState.READY
        generation += 1
        startedAtEpochMillis = now()
        emit(
            DeviceAgentEventType.LIFECYCLE,
            action,
            state = DeviceAgentLifecycleState.READY,
        )
        emit(
            DeviceAgentEventType.HEALTH,
            "updated",
            state = DeviceAgentLifecycleState.READY,
        )
    }

    fun reconnect() = start()

    fun disconnect() {
        if (lifecycleState == DeviceAgentLifecycleState.UNAVAILABLE) return
        val revoked = leases.values.sortedBy { it.leaseId }
        leases.clear()
        lifecycleState = DeviceAgentLifecycleState.UNAVAILABLE
        generation += 1
        startedAtEpochMillis = null
        revoked.forEach { lease ->
            emit(
                DeviceAgentEventType.LEASE,
                "revoked",
                leaseId = lease.leaseId,
                capUri = lease.capUri,
            )
        }
        emit(
            DeviceAgentEventType.LIFECYCLE,
            "disconnected",
            state = DeviceAgentLifecycleState.UNAVAILABLE,
        )
        emit(
            DeviceAgentEventType.HEALTH,
            "updated",
            state = DeviceAgentLifecycleState.UNAVAILABLE,
        )
    }

    fun markDegraded(reason: String) {
        if (lifecycleState == DeviceAgentLifecycleState.UNAVAILABLE) return
        lifecycleState = DeviceAgentLifecycleState.DEGRADED
        generation += 1
        emit(
            DeviceAgentEventType.LIFECYCLE,
            reason,
            state = DeviceAgentLifecycleState.DEGRADED,
        )
        emit(
            DeviceAgentEventType.HEALTH,
            "updated",
            state = DeviceAgentLifecycleState.DEGRADED,
        )
    }

    fun restore() {
        if (lifecycleState != DeviceAgentLifecycleState.DEGRADED) return
        lifecycleState = DeviceAgentLifecycleState.READY
        generation += 1
        emit(
            DeviceAgentEventType.LIFECYCLE,
            "restored",
            state = DeviceAgentLifecycleState.READY,
        )
        emit(
            DeviceAgentEventType.HEALTH,
            "updated",
            state = DeviceAgentLifecycleState.READY,
        )
    }

    fun health(): DeviceAgentHealth {
        val startedAt = startedAtEpochMillis
        val uptime = if (startedAt == null) 0 else maxOf(0, now() - startedAt)
        return DeviceAgentHealth(
            state = lifecycleState,
            generation = generation,
            uptimeMillis = uptime,
            capabilityCount = capabilityValues.size,
            availableCapabilityCount = capabilityValues.count {
                it.availability == Availability.AVAILABLE
            },
            busyCapabilityCount = capabilityValues.count {
                it.availability == Availability.BUSY
            },
            restrictedCapabilityCount = capabilityValues.count {
                it.availability == Availability.RESTRICTED
            },
            unavailableCapabilityCount = capabilityValues.count {
                it.availability == Availability.UNAVAILABLE
            },
            authorizedCapabilityCount = capabilityValues.count {
                it.authorization == Authorization.GRANTED
            },
            activeLeaseCount = leases.size,
        )
    }

    fun activeLeases(): List<DeviceAgentLease> =
        leases.values.sortedBy { it.leaseId }

    fun requestCapability(request: DeviceAgentCapabilityRequest): DeviceAgentLease {
        if (lifecycleState != DeviceAgentLifecycleState.READY &&
            lifecycleState != DeviceAgentLifecycleState.DEGRADED
        ) {
            throw failure(
                DeviceAgentErrorCode.AGENT_UNAVAILABLE,
                "the device agent is unavailable",
            )
        }
        if (!bounded(request.capUri, 512) ||
            request.operations.isEmpty() ||
            request.operations.toSet().size != request.operations.size ||
            request.operations.any { !bounded(it, 128) } ||
            !bounded(request.workspaceId, 512) ||
            !bounded(request.applicationId, 512) ||
            !bounded(request.requesterDeviceId, 512) ||
            !bounded(request.sessionId, 512) ||
            request.leaseId?.let { !bounded(it, 512) } == true ||
            request.auditId?.let { !bounded(it, 512) } == true
        ) {
            throw failure(
                DeviceAgentErrorCode.INVALID_REQUEST,
                "required capability request fields are missing",
            )
        }
        val capability = capabilityValues.firstOrNull {
            it.capUri == request.capUri
        } ?: throw failure(
            DeviceAgentErrorCode.CAPABILITY_UNKNOWN,
            "capability ${request.capUri} is not advertised",
            request.capUri,
        )
        request.operations.forEach { operation ->
            if (operation !in capability.operations) {
                throw failure(
                    DeviceAgentErrorCode.OPERATION_NOT_ALLOWED,
                    "operation $operation is not allowed",
                    operation,
                )
            }
        }
        when (capability.authorization) {
            Authorization.GRANTED -> Unit
            Authorization.REVOKED -> throw failure(
                DeviceAgentErrorCode.AUTHORIZATION_REVOKED,
                "the capability authorization was revoked",
            )
            Authorization.UNGRANTED,
            Authorization.DENIED -> throw failure(
                DeviceAgentErrorCode.AUTHORIZATION_DENIED,
                "the capability is not authorized",
            )
        }
        when (capability.availability) {
            Availability.AVAILABLE -> Unit
            Availability.BUSY -> throw failure(
                DeviceAgentErrorCode.CAPABILITY_BUSY,
                "the capability is temporarily busy",
            )
            Availability.RESTRICTED -> throw failure(
                DeviceAgentErrorCode.CAPABILITY_RESTRICTED,
                "the capability is restricted by policy",
            )
            Availability.UNAVAILABLE -> throw failure(
                DeviceAgentErrorCode.CAPABILITY_UNAVAILABLE,
                "the capability is unavailable",
            )
        }
        capability.permissions.forEach { permission ->
            if (permissionStates[permission] != DeviceAgentPlatformPermissionState.GRANTED) {
                throw failure(
                    DeviceAgentErrorCode.PLATFORM_PERMISSION_DENIED,
                    "platform permission $permission is not granted",
                    permission,
                )
            }
        }

        nextLeaseOrdinal += 1
        val leaseId = request.leaseId ?: "lease-$nextLeaseOrdinal"
        if (leases.containsKey(leaseId)) {
            throw failure(
                DeviceAgentErrorCode.INVALID_REQUEST,
                "lease $leaseId is already active",
                leaseId,
            )
        }
        val issuedAt = now()
        val lease = DeviceAgentLease(
            leaseId = leaseId,
            auditId = request.auditId ?: "audit-$nextLeaseOrdinal",
            capUri = capability.capUri,
            operations = request.operations.toList(),
            workspaceId = request.workspaceId,
            applicationId = request.applicationId,
            requesterDeviceId = request.requesterDeviceId,
            sessionId = request.sessionId,
            issuedAtEpochMillis = issuedAt,
            expiresAtEpochMillis = issuedAt + leaseDurationMillis,
        )
        leases[leaseId] = lease
        emit(
            DeviceAgentEventType.LEASE,
            "granted",
            leaseId = leaseId,
            capUri = capability.capUri,
        )
        emit(
            DeviceAgentEventType.HEALTH,
            "updated",
            state = lifecycleState,
        )
        return lease
    }

    fun releaseCapability(leaseId: String) {
        val lease = leases.remove(leaseId) ?: throw failure(
            DeviceAgentErrorCode.LEASE_NOT_FOUND,
            "lease $leaseId is not active",
            leaseId,
        )
        emit(
            DeviceAgentEventType.LEASE,
            "released",
            leaseId = leaseId,
            capUri = lease.capUri,
        )
        emit(
            DeviceAgentEventType.HEALTH,
            "updated",
            state = lifecycleState,
        )
    }

    fun subscribe(
        eventType: String,
        handler: (DeviceAgentEvent) -> Unit,
    ): DeviceAgentSubscription {
        val type = DeviceAgentEventType.fromWire(eventType) ?: throw failure(
            DeviceAgentErrorCode.INVALID_EVENT_TYPE,
            "subscription event type $eventType is invalid",
            eventType,
        )
        nextSubscriptionId += 1
        val subscriptionId = nextSubscriptionId
        subscriptions[subscriptionId] = Subscription(type, handler)
        return DeviceAgentSubscription {
            subscriptions.remove(subscriptionId)
        }
    }

    private fun emit(
        type: DeviceAgentEventType,
        action: String,
        leaseId: String? = null,
        capUri: String? = null,
        state: DeviceAgentLifecycleState? = null,
        permission: String? = null,
    ) {
        val matching = subscriptions.values.filter { it.type == type }
        if (matching.isEmpty()) return
        matching.forEach { subscription ->
            nextSequence += 1
            subscription.handler(
                DeviceAgentEvent(
                    type = type,
                    sequence = nextSequence,
                    atEpochMillis = now(),
                    action = action,
                    leaseId = leaseId,
                    capUri = capUri,
                    state = state,
                    permission = permission,
                ),
            )
        }
    }

    private fun bounded(value: String, maximum: Int): Boolean =
        value.isNotBlank() && value.length <= maximum

    private fun failure(
        code: DeviceAgentErrorCode,
        message: String,
        detail: String? = null,
    ): DeviceAgentException = DeviceAgentException(code, message, detail)
}
