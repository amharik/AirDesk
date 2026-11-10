package com.airdesk.android.remote

enum class RemoteSSHServicePhase {
    IDLE,
    STARTING,
    RUNNING,
    FAILED,
}

data class RemoteSSHServiceSnapshot(
    val phase: RemoteSSHServicePhase,
    val status: String,
    val activeClientId: String?,
    val attachedClientIds: Set<String>,
    val lastExitMessage: String?,
    val auditEvents: List<RemoteSSHAuditEvent>,
) {
    val isRunning: Boolean
        get() = phase == RemoteSSHServicePhase.RUNNING
}

data class RemoteSSHServiceEvent(
    val clientId: String?,
    val event: RemoteSSHEvent,
)

class RemoteSSHServiceController(
    val terminal: RemoteSSHTerminal,
) {
    private val lock = Any()
    private val attachedClients = LinkedHashSet<String>()
    private val listeners = LinkedHashSet<(RemoteSSHServiceSnapshot) -> Unit>()
    private val eventListeners = LinkedHashSet<(RemoteSSHServiceEvent) -> Unit>()
    private var phase = RemoteSSHServicePhase.IDLE
    private var status = "Idle"
    private var activeClientId: String? = null
    private var lastExitMessage: String? = null

    init {
        terminal.onEvent = ::handleTerminalEvent
    }

    fun snapshot(): RemoteSSHServiceSnapshot = synchronized(lock) {
        RemoteSSHServiceSnapshot(
            phase = phase,
            status = status,
            activeClientId = activeClientId,
            attachedClientIds = attachedClients.toSet(),
            lastExitMessage = lastExitMessage,
            auditEvents = terminal.auditEvents,
        )
    }

    fun addListener(listener: (RemoteSSHServiceSnapshot) -> Unit) {
        synchronized(lock) {
            listeners.add(listener)
        }
    }

    fun removeListener(listener: (RemoteSSHServiceSnapshot) -> Unit) {
        synchronized(lock) {
            listeners.remove(listener)
        }
    }

    fun addEventListener(listener: (RemoteSSHServiceEvent) -> Unit) {
        synchronized(lock) {
            eventListeners.add(listener)
        }
    }

    fun removeEventListener(listener: (RemoteSSHServiceEvent) -> Unit) {
        synchronized(lock) {
            eventListeners.remove(listener)
        }
    }

    fun attach(clientId: String): RemoteSSHServiceSnapshot {
        require(clientId.isNotBlank() && clientId.length <= 128) {
            "client id must be non-blank and at most 128 characters"
        }
        synchronized(lock) {
            attachedClients.add(clientId)
            activeClientId = clientId
            if (phase == RemoteSSHServicePhase.RUNNING) {
                status = "Attached to the running remote terminal"
            }
        }
        return publish()
    }

    fun detach(clientId: String): RemoteSSHServiceSnapshot {
        synchronized(lock) {
            attachedClients.remove(clientId)
            if (activeClientId == clientId) {
                activeClientId = null
                if (phase == RemoteSSHServicePhase.RUNNING) {
                    status = "Remote terminal running without an attached client"
                }
            }
        }
        return publish()
    }

    fun start(
        configuration: RemoteSSHConfiguration,
        size: RemoteSSHSize,
        context: RemoteSSHContext,
        clientId: String,
    ): RemoteSSHServiceSnapshot {
        synchronized(lock) {
            attachedClients.add(clientId)
            activeClientId = clientId
            phase = RemoteSSHServicePhase.STARTING
            status = "Connecting to ${configuration.username}@${configuration.host}..."
            lastExitMessage = null
        }
        publish()
        try {
            terminal.start(configuration, size, context)
        } catch (error: Throwable) {
            synchronized(lock) {
                phase = RemoteSSHServicePhase.FAILED
                status = error.message ?: "Remote terminal failed to start"
                lastExitMessage = status
            }
            publish()
            throw error
        }
        return snapshot()
    }

    fun write(data: ByteArray, clientId: String) {
        if (!isActiveClient(clientId)) return
        terminal.write(data)
    }

    fun resize(columns: Int, rows: Int, clientId: String) {
        if (!isActiveClient(clientId)) return
        terminal.resize(columns, rows)
    }

    fun stop(): RemoteSSHServiceSnapshot {
        terminal.stop()
        synchronized(lock) {
            phase = RemoteSSHServicePhase.IDLE
            status = "Idle"
            lastExitMessage = null
        }
        return publish()
    }

    fun shutdown() {
        terminal.shutdown()
        synchronized(lock) {
            phase = RemoteSSHServicePhase.IDLE
            status = "Stopped"
            activeClientId = null
            attachedClients.clear()
        }
        publish()
    }

    private fun isActiveClient(clientId: String): Boolean = synchronized(lock) {
        activeClientId == clientId && phase == RemoteSSHServicePhase.RUNNING
    }

    private fun handleTerminalEvent(event: RemoteSSHEvent) {
        val target = synchronized(lock) {
            when (event) {
                RemoteSSHEvent.Ready -> {
                    phase = RemoteSSHServicePhase.RUNNING
                    status = "Connected to the remote terminal"
                }
                is RemoteSSHEvent.Data -> Unit
                is RemoteSSHEvent.Exit -> {
                    phase = RemoteSSHServicePhase.FAILED
                    status = event.message ?: "The SSH session ended."
                    lastExitMessage = status
                }
            }
            activeClientId
        }
        if (event !is RemoteSSHEvent.Data) {
            publish()
        }
        val serviceEvent = RemoteSSHServiceEvent(target, event)
        val currentListeners = synchronized(lock) { eventListeners.toList() }
        currentListeners.forEach { listener ->
            runCatching { listener(serviceEvent) }
        }
    }

    private fun publish(): RemoteSSHServiceSnapshot {
        val snapshot = snapshot()
        val currentListeners = synchronized(lock) { listeners.toList() }
        currentListeners.forEach { listener ->
            runCatching { listener(snapshot) }
        }
        return snapshot
    }
}
