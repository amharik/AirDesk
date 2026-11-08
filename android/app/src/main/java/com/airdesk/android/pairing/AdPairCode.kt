package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId
import com.airdesk.android.util.Base64Url
import java.security.KeyFactory
import java.security.SecureRandom
import java.security.interfaces.ECPublicKey
import java.security.spec.X509EncodedKeySpec
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class AdPairChannelBinding(
    val kind: String,
    val value: String,
)

@Serializable
data class AdPairOffer(
    val protocol: String = PROTOCOL,
    val version: String = VERSION,
    val type: String = TYPE_OFFER,
    val deviceId: String,
    val publicKey: String,
    val nonce: String,
    val replyTo: String? = null,
    val expiresAt: Long,
    val endpointHint: String? = null,
    val relayHint: String? = null,
    val capabilities: List<String> = emptyList(),
    val channelBinding: AdPairChannelBinding,
) {
    companion object {
        const val PROTOCOL = "adfp"
        const val VERSION = "0.1"
        const val TYPE_OFFER = "offer"
    }
}

@Serializable
data class AdPairCode(
    val protocol: String = AdPairCodec.PROTOCOL,
    val version: Int = AdPairCodec.VERSION,
    val mode: String,
    val salt: String,
    val secret: String? = null,
    val offer: AdPairOffer,
)

data class AdPairChallenge(
    val code: AdPairCode,
    val serialized: String,
    val mode: String,
    val salt: ByteArray,
    val expiresAt: Long,
    val pin: String?,
    val secret: ByteArray?,
)

enum class AdPairCodeErrorCode {
    INVALID_CODE,
    MALFORMED_CODE,
    UNSUPPORTED_CODE_VERSION,
    INVALID_MODE,
    INVALID_SALT,
    INVALID_SECRET,
    INVALID_PIN,
    EXPIRED_CODE,
    PIN_LOCKED,
}

class AdPairCodeException(
    val code: AdPairCodeErrorCode,
    message: String,
) : IllegalArgumentException(message)

object AdPairCodec {
    const val PROTOCOL = "adpair1"
    const val VERSION = 1
    const val PREFIX = "ADPAIR1:"
    const val MODE_PIN = "pin"
    const val MODE_QR_SECRET = "qr-secret"

    const val PIN_DIGITS = 6
    const val MIN_SALT_BYTES = 16
    const val MAX_SALT_BYTES = 64
    const val MIN_SECRET_BYTES = 16
    const val MAX_SECRET_BYTES = 64
    const val MAX_CODE_LENGTH = 16_384

    private const val MAX_CAPABILITIES = 64
    private const val MAX_CAPABILITY_LENGTH = 200
    private const val MIN_NONCE_BYTES = 16
    private const val MAX_NONCE_BYTES = 64
    private const val MAX_HINT_LENGTH = 2048
    private const val MAX_PUBLIC_KEY_LENGTH = 2048
    private val deviceIdPattern = Regex("^ad-device:[0-9a-f]{64}$")
    private val certificateHashPattern = Regex("^[0-9a-fA-F]{64}$")

    val json: Json = Json {
        ignoreUnknownKeys = false
        isLenient = false
        coerceInputValues = false
        explicitNulls = false
        encodeDefaults = true
    }

    fun serialize(code: AdPairCode): String =
        PREFIX + Base64Url.encode(json.encodeToString(code).toByteArray(Charsets.UTF_8))

    fun parse(
        raw: String,
        nowEpochMillis: Long,
        expectedMode: String? = null,
        localDeviceId: String? = null,
    ): AdPairCode {
        if (raw.isEmpty() || raw.length > MAX_CODE_LENGTH || !raw.startsWith(PREFIX)) {
            fail(AdPairCodeErrorCode.INVALID_CODE, "invalid pairing code")
        }
        val encoded = raw.substring(PREFIX.length)
        val data = try {
            Base64Url.decode(encoded)
        } catch (error: Exception) {
            fail(AdPairCodeErrorCode.MALFORMED_CODE, "pairing code is not valid base64url")
        }
        if (data.isEmpty()) {
            fail(AdPairCodeErrorCode.MALFORMED_CODE, "pairing code is empty")
        }
        val code = try {
            json.decodeFromString<AdPairCode>(data.toString(Charsets.UTF_8))
        } catch (error: Exception) {
            fail(AdPairCodeErrorCode.MALFORMED_CODE, "pairing code is not valid JSON")
        }
        validate(code, nowEpochMillis, expectedMode, localDeviceId)
        return code
    }

    fun createPinChallenge(
        offer: AdPairOffer,
        nowEpochMillis: Long,
        randomBytes: (Int) -> ByteArray = { count -> ByteArray(count).also { SecureRandom().nextBytes(it) } },
    ): AdPairChallenge {
        validateOffer(offer, nowEpochMillis, null)
        val pin = randomPin(randomBytes)
        val salt = randomBytes(32)
        if (salt.size != 32) fail(AdPairCodeErrorCode.INVALID_SALT, "random salt has the wrong length")
        val code = AdPairCode(mode = MODE_PIN, salt = Base64Url.encode(salt), offer = offer)
        return AdPairChallenge(
            code = code,
            serialized = serialize(code),
            mode = MODE_PIN,
            salt = salt,
            expiresAt = offer.expiresAt,
            pin = pin,
            secret = null,
        )
    }

    fun createQrSecretChallenge(
        offer: AdPairOffer,
        nowEpochMillis: Long,
        randomBytes: (Int) -> ByteArray = { count -> ByteArray(count).also { SecureRandom().nextBytes(it) } },
    ): AdPairChallenge {
        validateOffer(offer, nowEpochMillis, null)
        val secret = randomBytes(32)
        val salt = randomBytes(32)
        if (salt.size != 32) fail(AdPairCodeErrorCode.INVALID_SALT, "random salt has the wrong length")
        if (secret.size != 32) fail(AdPairCodeErrorCode.INVALID_SECRET, "random secret has the wrong length")
        val code = AdPairCode(
            mode = MODE_QR_SECRET,
            salt = Base64Url.encode(salt),
            secret = Base64Url.encode(secret),
            offer = offer,
        )
        return AdPairChallenge(
            code = code,
            serialized = serialize(code),
            mode = MODE_QR_SECRET,
            salt = salt,
            expiresAt = offer.expiresAt,
            pin = null,
            secret = secret,
        )
    }

    fun deriveRegistration(
        code: AdPairCode,
        pin: String?,
        initiatorDeviceId: String,
        responderDeviceId: String,
    ): Spake2PlusPasswordRegistration {
        if (initiatorDeviceId.isEmpty() || responderDeviceId.isEmpty() || initiatorDeviceId == responderDeviceId) {
            fail(AdPairCodeErrorCode.INVALID_CODE, "invalid pairing device identifiers")
        }
        val password = when (code.mode) {
            MODE_PIN -> {
                if (code.secret != null) fail(AdPairCodeErrorCode.INVALID_SECRET, "PIN code must not contain a secret")
                if (pin == null || !isValidPin(pin)) fail(AdPairCodeErrorCode.INVALID_PIN, "PIN must be 6 digits")
                pin.toByteArray(Charsets.UTF_8)
            }
            MODE_QR_SECRET -> {
                val secret = try {
                    code.secret?.let(Base64Url::decode)
                } catch (error: Exception) {
                    null
                } ?: fail(AdPairCodeErrorCode.INVALID_SECRET, "invalid QR pairing secret")
                if (secret.size !in MIN_SECRET_BYTES..MAX_SECRET_BYTES) {
                    fail(AdPairCodeErrorCode.INVALID_SECRET, "invalid QR pairing secret")
                }
                secret
            }
            else -> fail(AdPairCodeErrorCode.INVALID_MODE, "pairing code mode must be pin or qr-secret")
        }
        val salt = try {
            Base64Url.decode(code.salt)
        } catch (error: Exception) {
            fail(AdPairCodeErrorCode.INVALID_SALT, "invalid pairing salt")
        }
        if (salt.size !in MIN_SALT_BYTES..MAX_SALT_BYTES) {
            fail(AdPairCodeErrorCode.INVALID_SALT, "invalid pairing salt")
        }
        return Spake2PlusRegistration.createBytes(
            password = password,
            salt = salt,
            idProver = initiatorDeviceId.toByteArray(Charsets.UTF_8),
            idVerifier = responderDeviceId.toByteArray(Charsets.UTF_8),
        )
    }

    fun isValidPin(pin: String): Boolean = pin.length == PIN_DIGITS && pin.all { it in '0'..'9' }

    private fun validate(
        code: AdPairCode,
        nowEpochMillis: Long,
        expectedMode: String?,
        localDeviceId: String?,
    ) {
        if (code.protocol != PROTOCOL || code.version != VERSION) {
            fail(AdPairCodeErrorCode.UNSUPPORTED_CODE_VERSION, "unsupported pairing code version")
        }
        if (code.mode != MODE_PIN && code.mode != MODE_QR_SECRET) {
            fail(AdPairCodeErrorCode.INVALID_MODE, "pairing code mode must be pin or qr-secret")
        }
        if (expectedMode != null && code.mode != expectedMode) {
            fail(AdPairCodeErrorCode.INVALID_MODE, "unexpected pairing code mode")
        }
        val salt = try {
            Base64Url.decode(code.salt)
        } catch (error: Exception) {
            fail(AdPairCodeErrorCode.INVALID_SALT, "invalid pairing salt")
        }
        if (salt.size !in MIN_SALT_BYTES..MAX_SALT_BYTES) {
            fail(AdPairCodeErrorCode.INVALID_SALT, "invalid pairing salt")
        }
        validateOffer(code.offer, nowEpochMillis, localDeviceId)
        when (code.mode) {
            MODE_PIN -> if (code.secret != null) {
                fail(AdPairCodeErrorCode.INVALID_SECRET, "PIN code must not contain a secret")
            }
            MODE_QR_SECRET -> {
                val secret = try {
                    code.secret?.let(Base64Url::decode)
                } catch (error: Exception) {
                    null
                }
                if (secret == null || secret.size !in MIN_SECRET_BYTES..MAX_SECRET_BYTES) {
                    fail(AdPairCodeErrorCode.INVALID_SECRET, "invalid QR pairing secret")
                }
            }
        }
    }

    private fun validateOffer(offer: AdPairOffer, nowEpochMillis: Long, localDeviceId: String?) {
        if (offer.protocol != AdPairOffer.PROTOCOL || offer.version != AdPairOffer.VERSION) {
            fail(AdPairCodeErrorCode.INVALID_CODE, "unsupported pairing offer version")
        }
        if (offer.type != AdPairOffer.TYPE_OFFER || offer.replyTo != null) {
            fail(AdPairCodeErrorCode.INVALID_CODE, "pairing challenge requires an offer")
        }
        if (!deviceIdPattern.matches(offer.deviceId)) {
            fail(AdPairCodeErrorCode.INVALID_CODE, "invalid pairing device id")
        }
        if (localDeviceId != null && offer.deviceId == localDeviceId) {
            fail(AdPairCodeErrorCode.INVALID_CODE, "refusing to pair this device with itself")
        }
        if (offer.publicKey.isEmpty() || offer.publicKey.length > MAX_PUBLIC_KEY_LENGTH) {
            fail(AdPairCodeErrorCode.INVALID_CODE, "invalid pairing public key")
        }
        val spki = try {
            Base64Url.decode(offer.publicKey)
        } catch (error: Exception) {
            fail(AdPairCodeErrorCode.INVALID_CODE, "invalid pairing public key")
        }
        val publicKey = try {
            KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(spki)) as? ECPublicKey
        } catch (error: Exception) {
            null
        } ?: fail(AdPairCodeErrorCode.INVALID_CODE, "invalid pairing public key")
        if (publicKey.params.curve.field.fieldSize != 256) {
            fail(AdPairCodeErrorCode.INVALID_CODE, "pairing public key must use P-256")
        }
        if (DeviceId.fromSpki(spki) != offer.deviceId) {
            fail(AdPairCodeErrorCode.INVALID_CODE, "pairing device id does not match its public key")
        }
        val nonce = try {
            Base64Url.decode(offer.nonce)
        } catch (error: Exception) {
            fail(AdPairCodeErrorCode.INVALID_CODE, "invalid pairing nonce")
        }
        if (nonce.size !in MIN_NONCE_BYTES..MAX_NONCE_BYTES) {
            fail(AdPairCodeErrorCode.INVALID_CODE, "invalid pairing nonce")
        }
        if (offer.expiresAt <= nowEpochMillis) {
            fail(AdPairCodeErrorCode.EXPIRED_CODE, "pairing code has expired")
        }
        validateHint(offer.endpointHint)
        validateHint(offer.relayHint)
        if (offer.capabilities.size > MAX_CAPABILITIES ||
            offer.capabilities.any { it.isEmpty() || it.length > MAX_CAPABILITY_LENGTH } ||
            offer.capabilities.toSet().size != offer.capabilities.size
        ) {
            fail(AdPairCodeErrorCode.INVALID_CODE, "invalid pairing capabilities")
        }
        validateBinding(offer.channelBinding)
    }

    private fun validateHint(value: String?) {
        if (value != null && (value.isEmpty() || value.length > MAX_HINT_LENGTH)) {
            fail(AdPairCodeErrorCode.INVALID_CODE, "invalid pairing endpoint hint")
        }
    }

    private fun validateBinding(binding: AdPairChannelBinding) {
        if (binding.kind == "certificate-hash") {
            if (!certificateHashPattern.matches(binding.value)) {
                fail(AdPairCodeErrorCode.INVALID_CODE, "invalid certificate hash binding")
            }
            return
        }
        if (binding.kind == "exporter") {
            val bytes = try {
                Base64Url.decode(binding.value)
            } catch (error: Exception) {
                null
            }
            if (bytes == null || bytes.size < 16) {
                fail(AdPairCodeErrorCode.INVALID_CODE, "invalid exporter binding")
            }
            return
        }
        fail(AdPairCodeErrorCode.INVALID_CODE, "unsupported pairing channel binding")
    }

    private fun randomPin(randomBytes: (Int) -> ByteArray): String {
        val range = 1L shl 32
        val limit = range - (range % 1_000_000)
        repeat(64) {
            val bytes = randomBytes(4)
            if (bytes.size != 4) fail(AdPairCodeErrorCode.INVALID_PIN, "random PIN has the wrong length")
            var word = 0L
            bytes.forEach { byte -> word = (word shl 8) or (byte.toLong() and 0xff) }
            if (word < limit) {
                return (word % 1_000_000).toString().padStart(PIN_DIGITS, '0')
            }
        }
        fail(AdPairCodeErrorCode.INVALID_PIN, "could not generate a PIN")
    }

    private fun fail(code: AdPairCodeErrorCode, message: String): Nothing =
        throw AdPairCodeException(code, message)
}

class AdPairPinAttemptGuard(
    private val maxAttempts: Int = 5,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private data class AttemptState(var failures: Int, var expiresAt: Long)

    private val attempts = mutableMapOf<String, AttemptState>()

    init {
        require(maxAttempts > 0) { "maxAttempts must be positive" }
    }

    @Synchronized
    fun assertAllowed(key: String, expiresAt: Long) {
        pruneExpired()
        if (expiresAt <= now()) {
            throw AdPairCodeException(AdPairCodeErrorCode.EXPIRED_CODE, "pairing code has expired")
        }
        val state = attempts[key]
        if (state != null && state.failures >= maxAttempts) {
            throw AdPairCodeException(AdPairCodeErrorCode.PIN_LOCKED, "pairing PIN is locked")
        }
    }

    @Synchronized
    fun recordFailure(key: String, expiresAt: Long): Int {
        pruneExpired()
        if (expiresAt <= now()) {
            throw AdPairCodeException(AdPairCodeErrorCode.EXPIRED_CODE, "pairing code has expired")
        }
        var state = attempts[key] ?: AttemptState(0, expiresAt)
        if (state.failures >= maxAttempts) {
            throw AdPairCodeException(AdPairCodeErrorCode.PIN_LOCKED, "pairing PIN is locked")
        }
        state.failures += 1
        state.expiresAt = maxOf(state.expiresAt, expiresAt)
        attempts[key] = state
        return maxOf(0, maxAttempts - state.failures)
    }

    @Synchronized
    fun remainingAttempts(key: String): Int = maxOf(0, maxAttempts - (attempts[key]?.failures ?: 0))

    @Synchronized
    fun reset(key: String) {
        attempts.remove(key)
    }

    private fun pruneExpired() {
        val current = now()
        attempts.entries.removeAll { it.value.expiresAt <= current }
    }
}
