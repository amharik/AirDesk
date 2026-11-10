package com.airdesk.android.remote

import com.jcraft.jsch.Channel
import com.jcraft.jsch.ChannelExec
import com.jcraft.jsch.ChannelShell
import com.jcraft.jsch.HostKey
import com.jcraft.jsch.HostKeyRepository
import com.jcraft.jsch.JSch
import com.jcraft.jsch.Session
import com.jcraft.jsch.UserInfo
import java.io.InputStream
import java.io.OutputStream
import java.net.SocketTimeoutException
import java.util.Base64
import java.util.concurrent.atomic.AtomicBoolean

class JschRemoteSSHTransport : RemoteSSHTransport {
    override fun open(
        configuration: RemoteSSHConfiguration,
        size: RemoteSSHSize,
        onData: (ByteArray) -> Unit,
        onClosed: (Throwable?) -> Unit,
    ): RemoteSSHConnection {
        val normalized = configuration.validate()
        size.validate()
        val pinned = PinnedHostKey.parse(normalized.hostKey)
        val jsch = JSch()
        jsch.hostKeyRepository = PinnedHostKeyRepository(pinned)
        var session: Session? = null
        var channel: TerminalChannel? = null
        var channelRequested = false
        try {
            session = jsch.getSession(normalized.username, normalized.host, normalized.port)
            session.setPassword(normalized.password)
            session.setConfig("StrictHostKeyChecking", "yes")
            session.setConfig("PreferredAuthentications", "password,keyboard-interactive")
            session.setServerAliveInterval(30_000)
            session.setServerAliveCountMax(3)
            session.connect(normalized.connectTimeoutMillis)

            channelRequested = true
            val opened = if (normalized.startupCommand != null) {
                val exec = session.openChannel("exec") as ChannelExec
                exec.setCommand(normalized.startupCommand)
                TerminalChannel(exec)
            } else {
                TerminalChannel(session.openChannel("shell") as ChannelShell)
            }
            channel = opened
            opened.setPtyType(
                normalized.terminalType,
                size.columns,
                size.rows,
                size.pixelWidth,
                size.pixelHeight,
            )
            opened.connect(normalized.connectTimeoutMillis)

            return JschConnection(
                session = session,
                channel = opened,
                input = opened.inputStream,
                output = opened.outputStream,
                onData = onData,
                onClosed = onClosed,
            )
        } catch (error: Throwable) {
            runCatching { channel?.disconnect() }
            runCatching { session?.disconnect() }
            throw mapFailure(
                error,
                if (channelRequested) {
                    RemoteSSHErrorCode.CHANNEL_REJECTED
                } else {
                    RemoteSSHErrorCode.CONNECT_FAILED
                },
            )
        }
    }

    private fun mapFailure(
        error: Throwable,
        fallback: RemoteSSHErrorCode,
    ): RemoteSSHException {
        val details = error.javaClass.simpleName + " " + (error.message ?: "")
        return when {
            details.contains("HostKey", ignoreCase = true) ||
                details.contains("host key", ignoreCase = true) -> RemoteSSHException(
                RemoteSSHErrorCode.HOST_KEY_MISMATCH,
                "The SSH host key does not match the pinned key.",
                error,
            )
            details.contains("Auth", ignoreCase = true) ||
                details.contains("authentication", ignoreCase = true) -> RemoteSSHException(
                RemoteSSHErrorCode.AUTHENTICATION_FAILED,
                "The SSH server did not accept the configured credentials.",
                error,
            )
            error is SocketTimeoutException -> RemoteSSHException(
                RemoteSSHErrorCode.CONNECT_FAILED,
                "The SSH connection timed out.",
                error,
            )
            fallback == RemoteSSHErrorCode.CHANNEL_REJECTED -> RemoteSSHException(
                RemoteSSHErrorCode.CHANNEL_REJECTED,
                "The SSH server rejected the terminal request.",
                error,
            )
            else -> RemoteSSHException(
                RemoteSSHErrorCode.CONNECT_FAILED,
                "The SSH server could not be reached or did not accept the connection.",
                error,
            )
        }
    }

    private class PinnedHostKeyRepository(
        private val expected: PinnedHostKey,
    ) : HostKeyRepository {
        override fun check(host: String, key: ByteArray): Int {
            val actual = Base64.getEncoder().encodeToString(key)
            return if (actual == expected.base64) {
                HostKeyRepository.OK
            } else {
                HostKeyRepository.CHANGED
            }
        }

        override fun add(hostkey: HostKey?, ui: UserInfo?) = Unit

        override fun remove(host: String?, type: String?) = Unit

        override fun remove(host: String?, type: String?, key: ByteArray?) = Unit

        override fun getKnownHostsRepositoryID(): String = "airdesk-pinned-host-key"

        override fun getHostKey(): Array<HostKey> = emptyArray()

        override fun getHostKey(host: String?, type: String?): Array<HostKey> = emptyArray()
    }

    private class TerminalChannel(private val channel: Channel) {
        fun setPtyType(
            terminalType: String,
            columns: Int,
            rows: Int,
            pixelWidth: Int,
            pixelHeight: Int,
        ) {
            when (val target = channel) {
                is ChannelShell -> target.setPtyType(
                    terminalType,
                    columns,
                    rows,
                    pixelWidth,
                    pixelHeight,
                )
                is ChannelExec -> target.setPtyType(
                    terminalType,
                    columns,
                    rows,
                    pixelWidth,
                    pixelHeight,
                )
            }
        }

        fun setPtySize(columns: Int, rows: Int) {
            when (val target = channel) {
                is ChannelShell -> target.setPtySize(columns, rows, 0, 0)
                is ChannelExec -> target.setPtySize(columns, rows, 0, 0)
            }
        }

        fun connect(timeoutMillis: Int) {
            channel.connect(timeoutMillis)
        }

        val inputStream: InputStream
            get() = channel.inputStream

        val outputStream: OutputStream
            get() = channel.outputStream

        fun disconnect() {
            channel.disconnect()
        }
    }

    private class JschConnection(
        private val session: Session,
        private val channel: TerminalChannel,
        private val input: InputStream,
        private val output: OutputStream,
        private val onData: (ByteArray) -> Unit,
        private val onClosed: (Throwable?) -> Unit,
    ) : RemoteSSHConnection {
        private val closed = AtomicBoolean(false)
        private val reader = Thread(
            {
                readLoop()
            },
            "AirDeskSSHReader",
        ).apply { isDaemon = true }

        override fun start() {
            reader.start()
        }

        override fun write(data: ByteArray) {
            if (closed.get()) {
                throw RemoteSSHException(
                    RemoteSSHErrorCode.CONNECTION_CLOSED,
                    "The SSH session is closed.",
                )
            }
            synchronized(output) {
                output.write(data)
                output.flush()
            }
        }

        override fun resize(columns: Int, rows: Int) {
            if (closed.get()) return
            channel.setPtySize(columns, rows)
        }

        override fun close() {
            if (!closed.compareAndSet(false, true)) return
            runCatching { channel.disconnect() }
            runCatching { session.disconnect() }
            runCatching { input.close() }
            runCatching { output.close() }
            reader.interrupt()
        }

        private fun readLoop() {
            val buffer = ByteArray(16 * 1_024)
            try {
                while (!closed.get()) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    if (read > 0) {
                        onData(buffer.copyOf(read))
                    }
                }
                if (closed.compareAndSet(false, true)) {
                    onClosed(null)
                }
            } catch (error: Throwable) {
                if (closed.compareAndSet(false, true)) {
                    onClosed(
                        RemoteSSHException(
                            RemoteSSHErrorCode.CONNECTION_CLOSED,
                            "The SSH connection closed unexpectedly.",
                            error,
                        ),
                    )
                }
            } finally {
                runCatching { channel.disconnect() }
                runCatching { session.disconnect() }
            }
        }
    }
}
