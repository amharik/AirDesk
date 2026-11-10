package com.airdesk.android.remote

import java.util.Base64

enum class RemoteSSHErrorCode {
    INVALID_CONFIGURATION,
    INVALID_HOST_KEY,
    CONNECT_FAILED,
    AUTHENTICATION_FAILED,
    HOST_KEY_MISMATCH,
    CHANNEL_REJECTED,
    CONNECTION_CLOSED,
    NOT_RUNNING,
    LEASE_DENIED,
    LEASE_REVOKED,
    LEASE_EXPIRED,
    LEASE_BUSY,
    LEASE_INVALID,
}

class RemoteSSHException(
    val code: RemoteSSHErrorCode,
    message: String,
    cause: Throwable? = null,
) : IllegalStateException(message, cause)

data class PinnedHostKey(
    val algorithm: String,
    val base64: String,
) {
    companion object {
        private val algorithms = setOf(
            "ssh-ed25519",
            "ssh-rsa",
            "ecdsa-sha2-nistp256",
            "ecdsa-sha2-nistp384",
            "ecdsa-sha2-nistp521",
        )

        fun parse(value: String): PinnedHostKey {
            val parts = value.trim().split(Regex("\\s+"))
            if (parts.size < 2) {
                throw RemoteSSHException(
                    RemoteSSHErrorCode.INVALID_HOST_KEY,
                    "Paste the server's pinned OpenSSH host key.",
                )
            }
            val algorithm = parts[0]
            if (algorithm !in algorithms) {
                throw RemoteSSHException(
                    RemoteSSHErrorCode.INVALID_HOST_KEY,
                    "The pinned host key algorithm is not supported.",
                )
            }
            val encoded = parts[1]
            val decoded = runCatching { Base64.getDecoder().decode(encoded) }.getOrNull()
            if (decoded == null || decoded.isEmpty()) {
                throw RemoteSSHException(
                    RemoteSSHErrorCode.INVALID_HOST_KEY,
                    "The pinned host key is not valid base64.",
                )
            }
            return PinnedHostKey(algorithm, encoded)
        }
    }
}

data class RemoteSSHConfiguration(
    val host: String,
    val port: Int = 22,
    val username: String,
    val password: String,
    val hostKey: String,
    val terminalType: String = "xterm-256color",
    val startupCommand: String? = "tmux new -A -s airdesk",
    val connectTimeoutMillis: Int = 15_000,
) {
    fun validate(): RemoteSSHConfiguration {
        val normalizedHost = host.trim()
        if (normalizedHost.isEmpty() || normalizedHost.length > 255 || normalizedHost.any { it.isWhitespace() }) {
            throw RemoteSSHException(
                RemoteSSHErrorCode.INVALID_CONFIGURATION,
                "Enter the SSH server host.",
            )
        }
        if (port !in 1..65_535) {
            throw RemoteSSHException(
                RemoteSSHErrorCode.INVALID_CONFIGURATION,
                "The SSH port must be between 1 and 65535.",
            )
        }
        val normalizedUsername = username.trim()
        if (normalizedUsername.isEmpty() || normalizedUsername.length > 128) {
            throw RemoteSSHException(
                RemoteSSHErrorCode.INVALID_CONFIGURATION,
                "Enter the SSH username.",
            )
        }
        if (password.isEmpty() || password.length > 4_096) {
            throw RemoteSSHException(
                RemoteSSHErrorCode.INVALID_CONFIGURATION,
                "Enter the SSH password.",
            )
        }
        val normalizedTerminalType = terminalType.trim()
        if (normalizedTerminalType.isEmpty() || normalizedTerminalType.length > 64) {
            throw RemoteSSHException(
                RemoteSSHErrorCode.INVALID_CONFIGURATION,
                "The terminal type is invalid.",
            )
        }
        val normalizedStartup = startupCommand?.trim()?.takeIf { it.isNotEmpty() }
        if (normalizedStartup != null && (normalizedStartup.length > 2_048 || normalizedStartup.contains('\u0000'))) {
            throw RemoteSSHException(
                RemoteSSHErrorCode.INVALID_CONFIGURATION,
                "The startup command is invalid.",
            )
        }
        if (connectTimeoutMillis !in 1_000..60_000) {
            throw RemoteSSHException(
                RemoteSSHErrorCode.INVALID_CONFIGURATION,
                "The SSH timeout must be between 1 and 60 seconds.",
            )
        }
        PinnedHostKey.parse(hostKey)
        return copy(
            host = normalizedHost,
            username = normalizedUsername,
            hostKey = hostKey.trim(),
            terminalType = normalizedTerminalType,
            startupCommand = normalizedStartup,
        )
    }
}

data class RemoteSSHSize(
    val columns: Int = 80,
    val rows: Int = 24,
    val pixelWidth: Int = 0,
    val pixelHeight: Int = 0,
) {
    fun validate(): RemoteSSHSize {
        if (columns !in 1..1_000 || rows !in 1..1_000) {
            throw RemoteSSHException(
                RemoteSSHErrorCode.INVALID_CONFIGURATION,
                "The terminal size is invalid.",
            )
        }
        if (pixelWidth !in 0..20_000 || pixelHeight !in 0..20_000) {
            throw RemoteSSHException(
                RemoteSSHErrorCode.INVALID_CONFIGURATION,
                "The terminal pixel size is invalid.",
            )
        }
        return this
    }
}

sealed interface RemoteSSHEvent {
    data object Ready : RemoteSSHEvent

    data class Data(val bytes: ByteArray) : RemoteSSHEvent

    data class Exit(val message: String?) : RemoteSSHEvent
}
