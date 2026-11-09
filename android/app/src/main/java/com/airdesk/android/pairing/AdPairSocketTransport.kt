package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId
import java.io.Closeable
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString

interface PairingSocketConnection : Closeable {
    fun send(data: ByteArray)
}

interface PairingSocketConnector {
    fun connect(url: String, listener: PairingSocketListener): PairingSocketConnection
}

interface PairingSocketListener {
    fun onOpen(certificateSha256: String?)
    fun onBinary(data: ByteArray)
    fun onClosed(code: Int, reason: String)
    fun onFailure(error: Throwable)
}

class OkHttpPairingSocketConnector(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS)
        .build(),
) : PairingSocketConnector {
    override fun connect(url: String, listener: PairingSocketListener): PairingSocketConnection {
        val request = Request.Builder().url(url).build()
        val socket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) =
                listener.onOpen(response.handshake?.peerCertificates?.firstOrNull()?.let { certificate ->
                    DeviceId.hexLowercase(java.security.MessageDigest.getInstance("SHA-256").digest(certificate.encoded))
                })
            override fun onMessage(webSocket: WebSocket, bytes: ByteString) =
                listener.onBinary(bytes.toByteArray())
            override fun onMessage(webSocket: WebSocket, text: String) =
                listener.onFailure(IllegalArgumentException("pairing transport requires binary messages"))
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) =
                listener.onClosed(code, reason)
            override fun onFailure(webSocket: WebSocket, error: Throwable, response: Response?) =
                listener.onFailure(error)
        })
        return object : PairingSocketConnection {
            override fun send(data: ByteArray) {
                if (!socket.send(data.toByteString())) {
                    throw IllegalStateException("pairing WebSocket rejected the message")
                }
            }

            override fun close() {
                socket.close(NORMAL_CLOSURE, "pairing closed")
                client.dispatcher.executorService.shutdown()
            }
        }
    }

    private companion object {
        const val NORMAL_CLOSURE = 1000
    }
}

class AdPairSocketTransport(
    private val session: AdPairWireSession,
    private val connector: PairingSocketConnector = OkHttpPairingSocketConnector(),
) : Closeable {
    private var connection: PairingSocketConnection? = null

    var lastError: String? = null
        private set

    val state: AdPairWireSession.State
        get() = session.state

    val shortAuthenticationString: String?
        get() = session.shortAuthenticationString

    fun connect(
        url: String,
        initialMessage: ByteArray? = null,
        expectedCertificateSha256: String? = null,
        onUpdate: (AdPairSocketTransport) -> Unit = {},
    ) {
        check(connection == null) { "pairing socket is already connected" }
        val listener = object : PairingSocketListener {
            override fun onOpen(certificateSha256: String?) {
                if (expectedCertificateSha256 != null &&
                    !certificateSha256.equals(expectedCertificateSha256, ignoreCase = true)
                ) {
                    lastError = "pairing channel certificate does not match the pairing binding"
                    connection?.close()
                    onUpdate(this@AdPairSocketTransport)
                    return
                }
                initialMessage?.let(::send)
                onUpdate(this@AdPairSocketTransport)
            }

            override fun onBinary(data: ByteArray) {
                try {
                    session.receive(data)?.let(::send)
                } catch (error: Exception) {
                    lastError = error.message ?: error.javaClass.simpleName
                }
                onUpdate(this@AdPairSocketTransport)
            }

            override fun onClosed(code: Int, reason: String) {
                if (session.state != AdPairWireSession.State.COMPLETED) {
                    lastError = "pairing socket closed ($code): $reason"
                }
                onUpdate(this@AdPairSocketTransport)
            }

            override fun onFailure(error: Throwable) {
                lastError = error.message ?: error.javaClass.simpleName
                onUpdate(this@AdPairSocketTransport)
            }
        }
        connection = connector.connect(url, listener)
    }

    fun confirmShortAuthenticationString(entered: String): AdPairKeySchedule.Keys =
        session.confirmShortAuthenticationString(entered)

    fun send(data: ByteArray) {
        val current = connection ?: error("pairing socket is not connected")
        current.send(data)
        lastError = null
    }

    override fun close() {
        connection?.close()
        connection = null
    }
}
