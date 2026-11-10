package com.airdesk.android.remote

import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

interface RemoteSSHConnection {
    fun start() = Unit

    fun write(data: ByteArray)

    fun resize(columns: Int, rows: Int)

    fun close()
}

interface RemoteSSHTransport {
    fun open(
        configuration: RemoteSSHConfiguration,
        size: RemoteSSHSize,
        onData: (ByteArray) -> Unit,
        onClosed: (Throwable?) -> Unit,
    ): RemoteSSHConnection
}

interface RemoteSSHDriver {
    val isRunning: Boolean
    var onEvent: ((RemoteSSHEvent) -> Unit)?

    fun start(configuration: RemoteSSHConfiguration, size: RemoteSSHSize)

    fun write(data: ByteArray)

    fun resize(columns: Int, rows: Int)

    fun stop()

    fun shutdown() = stop()
}

class RemoteSSHController(
    private val transport: RemoteSSHTransport,
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { task ->
        Thread(task, "AirDeskSSHTransport").apply { isDaemon = true }
    },
) : RemoteSSHDriver {
    private val lock = Any()
    private var generation = 0
    private var connection: RemoteSSHConnection? = null
    private var running = false

    override var onEvent: ((RemoteSSHEvent) -> Unit)? = null

    override val isRunning: Boolean
        get() = synchronized(lock) { running }

    override fun start(configuration: RemoteSSHConfiguration, size: RemoteSSHSize) {
        val normalizedConfiguration = configuration.validate()
        val normalizedSize = size.validate()
        stop()
        var token = 0
        synchronized(lock) {
            generation += 1
            token = generation
        }
        executor.execute {
            connect(token, normalizedConfiguration, normalizedSize)
        }
    }

    override fun write(data: ByteArray) {
        if (data.isEmpty()) return
        var target: RemoteSSHConnection? = null
        var token = 0
        synchronized(lock) {
            if (!running) return
            target = connection ?: return
            token = generation
        }
        runCatching { target?.write(data) }.onFailure { error ->
            finish(token, error)
        }
    }

    override fun resize(columns: Int, rows: Int) {
        var target: RemoteSSHConnection? = null
        var token = 0
        synchronized(lock) {
            if (!running) return
            target = connection ?: return
            token = generation
        }
        runCatching { target?.resize(columns, rows) }.onFailure { error ->
            finish(token, error)
        }
    }

    override fun stop() {
        var target: RemoteSSHConnection? = null
        synchronized(lock) {
            generation += 1
            running = false
            target = connection
            connection = null
        }
        runCatching { target?.close() }
    }

    override fun shutdown() {
        stop()
        executor.shutdownNow()
    }

    private fun connect(
        token: Int,
        configuration: RemoteSSHConfiguration,
        size: RemoteSSHSize,
    ) {
        try {
            val opened = transport.open(
                configuration = configuration,
                size = size,
                onData = { data -> emitData(token, data) },
                onClosed = { error -> finish(token, error) },
            )
            val accepted = synchronized(lock) {
                if (token != generation) {
                    false
                } else {
                    connection = opened
                    running = true
                    true
                }
            }
            if (accepted) {
                emit(RemoteSSHEvent.Ready)
                runCatching { opened.start() }.onFailure { error ->
                    finish(token, error)
                }
            } else {
                runCatching { opened.close() }
            }
        } catch (error: Throwable) {
            finish(token, error)
        }
    }

    private fun emitData(token: Int, data: ByteArray) {
        if (data.isEmpty()) return
        var offset = 0
        while (offset < data.size) {
            val end = minOf(offset + MAXIMUM_CHUNK_BYTES, data.size)
            val chunk = if (offset == 0 && end == data.size) {
                data
            } else {
                data.copyOfRange(offset, end)
            }
            synchronized(lock) {
                if (token != generation) return
            }
            emit(RemoteSSHEvent.Data(chunk))
            offset = end
        }
    }

    private fun finish(token: Int, error: Throwable?) {
        var target: RemoteSSHConnection? = null
        synchronized(lock) {
            if (token != generation) return
            generation += 1
            running = false
            target = connection
            connection = null
        }
        runCatching { target?.close() }
        val message = when (error) {
            is RemoteSSHException -> error.message
            null -> "The SSH session ended."
            else -> "The SSH session ended unexpectedly."
        }
        emit(RemoteSSHEvent.Exit(message))
    }

    private fun emit(event: RemoteSSHEvent) {
        runCatching { onEvent?.invoke(event) }
    }

    companion object {
        const val MAXIMUM_CHUNK_BYTES = 64 * 1_024
    }
}
