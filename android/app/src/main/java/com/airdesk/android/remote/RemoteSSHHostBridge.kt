package com.airdesk.android.remote

import com.airdesk.android.workspace.AndroidTerminalMessage
import java.util.Base64
import java.util.UUID

interface RemoteSSHHostOutput {
    fun sendTerminalReady()

    fun sendTerminalData(base64Data: String)

    fun sendTerminalStatus(status: String)

    fun sendTerminalExit(message: String)
}

class RemoteSSHHostBridge(
    private val controller: RemoteSSHServiceController,
    private val output: RemoteSSHHostOutput,
    private val configuration: () -> RemoteSSHConfiguration,
    private val context: () -> RemoteSSHContext,
    private val size: () -> RemoteSSHSize = { RemoteSSHSize() },
    private val clientId: String = UUID.randomUUID().toString(),
) {
    private val eventListener: (RemoteSSHServiceEvent) -> Unit = { event ->
        if (event.clientId == null || event.clientId == clientId) {
            deliver(event.event)
        }
    }
    private var activeConfiguration: RemoteSSHConfiguration? = null

    var onStartRequested: (() -> Unit)? = null
    var onStopRequested: (() -> Unit)? = null

    fun attach() {
        controller.addEventListener(eventListener)
        val snapshot = controller.attach(clientId)
        when (snapshot.phase) {
            RemoteSSHServicePhase.RUNNING -> {
                output.sendTerminalReady()
                output.sendTerminalStatus("Reattached to the running remote terminal")
            }
            RemoteSSHServicePhase.STARTING -> output.sendTerminalStatus(snapshot.status)
            RemoteSSHServicePhase.FAILED -> snapshot.lastExitMessage?.let(output::sendTerminalExit)
            RemoteSSHServicePhase.IDLE -> Unit
        }
    }

    fun detach() {
        controller.removeEventListener(eventListener)
        controller.detach(clientId)
    }

    fun handle(message: AndroidTerminalMessage) {
        when (message.action) {
            "start" -> start()
            "write" -> {
                val encoded = message.data ?: return
                val data = runCatching { Base64.getDecoder().decode(encoded) }.getOrNull()
                if (data == null || data.isEmpty()) {
                    output.sendTerminalExit("Invalid terminal input.")
                    return
                }
                controller.write(data, clientId)
            }
            "resize" -> {
                val columns = message.columns ?: return
                val rows = message.rows ?: return
                controller.resize(columns, rows, clientId)
            }
            "stop" -> {
                controller.stop()
                output.sendTerminalStatus("Remote terminal stopped")
                onStopRequested?.invoke()
            }
        }
    }

    private fun start() {
        val latestConfiguration = try {
            configuration()
        } catch (error: RemoteSSHException) {
            output.sendTerminalExit(error.message ?: "The remote terminal profile is invalid.")
            return
        } catch (error: Throwable) {
            output.sendTerminalExit("The remote terminal profile is invalid.")
            return
        }
        val current = controller.snapshot()
        val canReattach = current.phase == RemoteSSHServicePhase.RUNNING ||
            current.phase == RemoteSSHServicePhase.STARTING
        if (canReattach &&
            (activeConfiguration == null || activeConfiguration == latestConfiguration)
        ) {
            val attached = controller.attach(clientId)
            when (attached.phase) {
                RemoteSSHServicePhase.RUNNING -> {
                    output.sendTerminalReady()
                    output.sendTerminalStatus("Reattached to the running remote terminal")
                }
                RemoteSSHServicePhase.STARTING -> output.sendTerminalStatus(attached.status)
                else -> Unit
            }
            return
        }
        if (canReattach) {
            controller.stop()
        }
        onStartRequested?.invoke()
        try {
            controller.start(
                configuration = latestConfiguration,
                size = size(),
                context = context(),
                clientId = clientId,
            )
            activeConfiguration = latestConfiguration
            output.sendTerminalStatus(controller.snapshot().status)
        } catch (error: RemoteSSHException) {
            output.sendTerminalExit(error.message ?: "The remote terminal could not start.")
        } catch (error: Throwable) {
            output.sendTerminalExit("The remote terminal could not start.")
        }
    }

    private fun deliver(event: RemoteSSHEvent) {
        when (event) {
            RemoteSSHEvent.Ready -> {
                output.sendTerminalReady()
                output.sendTerminalStatus("Connected to the remote terminal")
            }
            is RemoteSSHEvent.Data -> {
                output.sendTerminalData(Base64.getEncoder().encodeToString(event.bytes))
            }
            is RemoteSSHEvent.Exit -> {
                output.sendTerminalExit(event.message ?: "The SSH session ended.")
            }
        }
    }
}
