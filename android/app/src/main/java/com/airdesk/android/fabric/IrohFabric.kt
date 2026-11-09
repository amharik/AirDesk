package com.airdesk.android.fabric

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.content.Context
import com.airdesk.android.identity.DeviceId
import com.airdesk.android.util.Base64Url
import computer.iroh.Connection
import computer.iroh.Endpoint
import computer.iroh.EndpointOptions
import computer.iroh.EndpointTicket
import computer.iroh.RelayMode
import computer.iroh.presetMinimal
import java.io.Closeable
import java.security.KeyStore
import java.security.SecureRandom
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

enum class IrohFabricChannel(val wire: UByte) {
    CONTROL(0u),
    MOVEMENT(1u),
    RUNTIME(2u),
    RESOURCE(3u),
    DISPLAY(4u),
    SYNC(5u),
    PAIRING(6u),
    INPUT_EDGES(0x81u);

    val isReliable: Boolean get() = this != MOVEMENT

    companion object {
        fun reliable(wire: UByte): IrohFabricChannel? =
            entries.firstOrNull { it.wire == wire && it.isReliable }
    }
}

sealed interface IrohFabricMessage {
    data class Reliable(val channel: IrohFabricChannel, val payload: ByteArray) : IrohFabricMessage
    data class Movement(val payload: ByteArray) : IrohFabricMessage
    data class Invalid(val reason: String) : IrohFabricMessage
}

class IrohFabricException(message: String, cause: Throwable? = null) : Exception(message, cause)

object IrohFabricFrame {
    const val MAXIMUM_RELIABLE_PAYLOAD = 1_048_576
    const val MOVEMENT_PAYLOAD_SIZE = 16

    fun encode(channel: IrohFabricChannel, payload: ByteArray): ByteArray {
        require(channel.isReliable) { "movement must use datagrams" }
        require(payload.size <= MAXIMUM_RELIABLE_PAYLOAD) { "frame exceeds the 1 MiB limit" }
        return ByteBuffer.allocate(1 + 4 + payload.size)
            .put(channel.wire.toByte())
            .putInt(payload.size)
            .put(payload)
            .array()
    }
}

data class IrohFabricPath(
    val id: String,
    val remoteAddress: String,
    val isSelected: Boolean,
    val isDirectIp: Boolean,
    val isRelay: Boolean,
    val rttMillis: ULong,
)

data class IrohFabricConnectionDiagnostics(
    val remoteEndpointId: String,
    val paths: List<IrohFabricPath>,
) {
    val selectedPath: IrohFabricPath? get() = paths.firstOrNull { it.isSelected }
    val isUsingRelay: Boolean get() = selectedPath?.isRelay == true
}

data class IrohFabricEndpointInfo(
    val endpointId: String,
    val ticket: String,
    val directAddresses: List<String>,
    val relayUrl: String?,
    val relayPolicy: String,
)

class IrohFabricConnection internal constructor(
    private val connection: Connection,
    private val scope: CoroutineScope,
) : Closeable {
    val remoteEndpointId: String = connection.remoteId().toString()
    private val messagesChannel = Channel<IrohFabricMessage>(Channel.BUFFERED)
    val messages: Flow<IrohFabricMessage> = messagesChannel.receiveAsFlow()
    private val receiveJobs = ConcurrentHashMap<String, Job>()

    init {
        receiveJobs["reliable"] = scope.launch { receiveReliableFrames() }
        receiveJobs["movement"] = scope.launch { receiveMovementDatagrams() }
        receiveJobs["closed"] = scope.launch {
            runCatching { connection.closed() }
            messagesChannel.close()
            receiveJobs.values.forEach { it.cancel() }
        }
    }

    suspend fun send(channel: IrohFabricChannel, payload: ByteArray) {
        if (channel == IrohFabricChannel.MOVEMENT) {
            require(payload.size == IrohFabricFrame.MOVEMENT_PAYLOAD_SIZE) {
                "movement datagrams must be exactly 16 bytes"
            }
            connection.sendDatagramWait(payload)
            return
        }
        val stream = connection.openBi()
        val send = stream.send()
        send.writeAll(IrohFabricFrame.encode(channel, payload))
        send.finish()
    }

    fun diagnostics(): IrohFabricConnectionDiagnostics = IrohFabricConnectionDiagnostics(
        remoteEndpointId = remoteEndpointId,
        paths = connection.paths().map {
            IrohFabricPath(
                id = it.id,
                remoteAddress = it.remoteAddr,
                isSelected = it.isSelected,
                isDirectIp = it.isIp,
                isRelay = it.isRelay,
                rttMillis = it.rttMs,
            )
        },
    )

    override fun close() {
        receiveJobs.values.forEach { it.cancel() }
        messagesChannel.close()
        runCatching { connection.close(0L, "airdesk-closed".toByteArray()) }
    }

    private suspend fun receiveReliableFrames() {
        while (true) {
            try {
                val stream = connection.acceptBi()
                val receive = stream.recv()
                val wire = receive.readExact(1u).first().toUByte()
                val channel = IrohFabricChannel.reliable(wire)
                if (channel == null) {
                    messagesChannel.send(IrohFabricMessage.Invalid("unknown reliable channel $wire"))
                    continue
                }
                val length = ByteBuffer.wrap(receive.readExact(4u)).int
                if (length < 0 || length > IrohFabricFrame.MAXIMUM_RELIABLE_PAYLOAD) {
                    messagesChannel.send(IrohFabricMessage.Invalid("reliable frame exceeds the 1 MiB limit"))
                    continue
                }
                val payload = receive.readExact(length.toUInt())
                messagesChannel.send(IrohFabricMessage.Reliable(channel, payload))
            } catch (error: Exception) {
                messagesChannel.send(IrohFabricMessage.Invalid(error.message ?: "reliable receive failed"))
                break
            }
        }
    }

    private suspend fun receiveMovementDatagrams() {
        while (true) {
            try {
                val payload = connection.readDatagram()
                if (payload.size != IrohFabricFrame.MOVEMENT_PAYLOAD_SIZE) {
                    messagesChannel.send(IrohFabricMessage.Invalid("movement datagram must be exactly 16 bytes"))
                    continue
                }
                messagesChannel.send(IrohFabricMessage.Movement(payload))
            } catch (error: Exception) {
                messagesChannel.send(IrohFabricMessage.Invalid(error.message ?: "datagram receive failed"))
                break
            }
        }
    }
}


class IrohIdentityStore(private val context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val lock = Any()

    fun loadOrCreate(): ByteArray = synchronized(lock) {
        prefs.getString(KEY_SEED, null)?.let { encoded ->
            return@synchronized decrypt(encoded).also { require(it.size == 32) }
        }
        prefs.getString(KEY_LEGACY_PLAINTEXT, null)?.let { encoded ->
            val seed = Base64Url.decode(encoded).also { require(it.size == 32) }
            prefs.edit()
                .putString(KEY_SEED, encrypt(seed))
                .remove(KEY_LEGACY_PLAINTEXT)
                .apply()
            return@synchronized seed
        }
        val seed = ByteArray(32).also { SecureRandom().nextBytes(it) }
        prefs.edit().putString(KEY_SEED, encrypt(seed)).apply()
        seed
    }

    private fun encrypt(plaintext: ByteArray): String {
        val key = secretKey()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val ciphertext = cipher.doFinal(plaintext)
        return Base64Url.encode(
            ByteBuffer.allocate(4 + cipher.iv.size + ciphertext.size)
                .putInt(cipher.iv.size)
                .put(cipher.iv)
                .put(ciphertext)
                .array(),
        )
    }

    private fun decrypt(encoded: String): ByteArray {
        val bytes = Base64Url.decode(encoded)
        val buffer = ByteBuffer.wrap(bytes)
        require(buffer.remaining() >= 4) { "stored Iroh identity is malformed" }
        val ivLength = buffer.int
        require(ivLength in 12..16 && buffer.remaining() > ivLength) {
            "stored Iroh identity is malformed"
        }
        val iv = ByteArray(ivLength).also(buffer::get)
        val ciphertext = ByteArray(buffer.remaining()).also(buffer::get)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        return cipher.doFinal(ciphertext)
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(false)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "airdesk.iroh.identity.v1"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val GCM_TAG_BITS = 128
        const val PREFS = "airdesk_iroh_identity"
        const val KEY_SEED = "encrypted_secret_key"
        const val KEY_LEGACY_PLAINTEXT = "secret_key"
    }
}
class IrohFabricPeer(
    context: Context,
    identitySeed: ByteArray? = null,
) : Closeable {
    private val appContext = context.applicationContext
    private val configuredIdentitySeed = identitySeed
    private var loadedIdentitySeed: ByteArray? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val incoming = Channel<IrohFabricConnection>(Channel.BUFFERED)
    val incomingConnections: Flow<IrohFabricConnection> = incoming.receiveAsFlow()
    private var endpoint: Endpoint? = null
    private var acceptJob: Job? = null

    suspend fun start(): IrohFabricEndpointInfo = withContext(Dispatchers.IO) {
        endpoint?.let { return@withContext info(it) }
        val identitySeed = configuredIdentitySeed ?: loadedIdentitySeed ?: IrohIdentityStore(appContext).loadOrCreate().also { loadedIdentitySeed = it }
        require(identitySeed.size == 32) { "Iroh identity must be a 32-byte secret" }
        val bound = Endpoint.bind(
            EndpointOptions(
                preset = presetMinimal(),
                secretKey = identitySeed,
                alpns = listOf(DEFAULT_ALPN),
                relayMode = RelayMode.disabled(),
            ),
        )
        endpoint = bound
        acceptJob = scope.launch { acceptLoop(bound) }
        return@withContext info(bound)
    }

    fun endpointInfo(): IrohFabricEndpointInfo = info(
        endpoint ?: throw IrohFabricException("Iroh endpoint has not been started"),
    )

    suspend fun connect(ticket: String): IrohFabricConnection = withContext(Dispatchers.IO) {
        val bound = endpoint ?: throw IrohFabricException("Iroh endpoint has not been started")
        val parsed = runCatching { EndpointTicket.fromString(ticket) }
            .getOrElse { throw IrohFabricException("Iroh ticket is invalid", it) }
        val connection = bound.connect(parsed.endpointAddr(), DEFAULT_ALPN)
        return@withContext IrohFabricConnection(connection, scope)
    }

    override fun close() {
        acceptJob?.cancel()
        acceptJob = null
        incoming.close()
        val bound = endpoint
        endpoint = null
        runBlocking { runCatching { bound?.shutdown() } }
        scope.cancel()
    }

    private suspend fun acceptLoop(bound: Endpoint) {
        while (true) {
            val next = bound.acceptNext() ?: break
            try {
                val accepting = next.accept()
                if (!accepting.alpn().contentEquals(DEFAULT_ALPN)) {
                    continue
                }
                val connection = accepting.connect()
                incoming.send(IrohFabricConnection(connection, scope))
            } catch (_: Exception) {
                continue
            }
        }
        incoming.close()
    }

    private fun info(bound: Endpoint): IrohFabricEndpointInfo {
        val address = bound.addr()
        return IrohFabricEndpointInfo(
            endpointId = address.id().toString(),
            ticket = EndpointTicket.fromAddr(address).toString(),
            directAddresses = address.directAddresses(),
            relayUrl = address.relayUrl(),
            relayPolicy = "direct-only",
        )
    }

    companion object {
        val DEFAULT_ALPN: ByteArray = "airdesk/fabric/1".toByteArray()
        fun certificateHash(certificate: ByteArray): String =
            DeviceId.hexLowercase(MessageDigest.getInstance("SHA-256").digest(certificate))
    }
}
