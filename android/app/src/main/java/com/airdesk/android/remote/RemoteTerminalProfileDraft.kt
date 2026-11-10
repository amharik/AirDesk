package com.airdesk.android.remote

data class RemoteTerminalProfileDraft(
    val enabled: Boolean = false,
    val host: String = "",
    val port: String = "22",
    val username: String = "",
    val password: String = "",
    val hostKey: String = "",
    val startupCommand: String = "tmux new -A -s airdesk",
) {
    val destination: String
        get() {
            val normalizedHost = host.trim()
            val normalizedUsername = username.trim()
            return when {
                normalizedHost.isEmpty() -> "SSH"
                normalizedUsername.isEmpty() -> normalizedHost
                else -> "$normalizedUsername@$normalizedHost"
            }
        }

    fun configuration(): RemoteSSHConfiguration = RemoteSSHConfiguration(
        host = host,
        port = port.toIntOrNull()
            ?: throw RemoteSSHException(
                RemoteSSHErrorCode.INVALID_CONFIGURATION,
                "The SSH port must be between 1 and 65535.",
            ),
        username = username,
        password = password,
        hostKey = hostKey,
        startupCommand = startupCommand,
    ).validate()

    fun configurationOrNull(): RemoteSSHConfiguration? =
        runCatching { configuration() }.getOrNull()
}
