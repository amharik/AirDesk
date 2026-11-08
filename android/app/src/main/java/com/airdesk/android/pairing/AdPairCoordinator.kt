package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId
import com.airdesk.android.util.Base64Url
import java.security.KeyFactory
import java.security.SecureRandom
import java.security.interfaces.ECPublicKey
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString

enum class AdPairCoordinatorError {
    INVALID_STATE,
    SELF_PAIRING,
    REVOKED_DEVICE,
    UNSUPPORTED_PROTOCOL,
    UNSUPPORTED_VERSION,
    UNEXPECTED_TYPE,
    INVALID_DEVICE_ID,
    INVALID_PUBLIC_KEY,
    INVALID_NONCE,
    INVALID_REPLY_TO,
    EXPIRED,
    INVALID_BINDING,
    BINDING_MISMATCH,
    INVALID_CAPABILITIES,
    INVALID_HINT,
    INVALID_SIGNATURE,
    TRANSCRIPT_MISMATCH,
}

class AdPairCoordinatorException(
    val code: AdPairCoordinatorError,
    message: String,
) : IllegalArgumentException(message)

fun interface AdPairSigner {
    fun sign(data: ByteArray): ByteArray
}

fun interface AdPairSignatureVerifier {
    fun verify(publicKeyBase64Url: String, data: ByteArray, signature: ByteArray): Boolean
}

class AdPairCoordinator(
    val role: Role,
    private val deviceId: String,
    private val publicKey: String,
    private val signer: AdPairSigner,
    private val verifier: AdPairSignatureVerifier,
    private val registry: PeerRegistry? = null,
    private val peerDisplayLabel: String? = null,
    private val now: () -> Long = { System.currentTimeMillis() },
    private val randomBytes: (Int) -> ByteArray = { count ->
        ByteArray(count).also(SecureRandom()::nextBytes)
    },
) {
    enum class Role {
        INITIATOR,
        RESPONDER,
    }

    enum class State {
        INITIAL,
        OFFER_CREATED,
        JOINED,
        AWAITING_VERIFIER_RESPONSE,
        AWAITING_INITIATOR,
        COMPLETED,
    }

    data class InitiatorStart(val offer: AdPairOffer, val challenge: AdPairChallenge)

    data class ResponderJoin(
        val offer: AdPairOffer,
        val response: AdPairOffer,
        val responseData: ByteArray,
    )

    data class ResponderResponse(
        val share: ByteArray,
        val confirmation: ByteArray,
        val signature: ByteArray,
    )

    data class Result(
        val offer: AdPairOffer,
        val response: AdPairOffer,
        val transcript: ByteArray,
        val transcriptHash: ByteArray,
        val shortAuthenticationString: String,
        val channelBinding: AdPairChannelBinding,
        val capabilities: List<String>,
        val initiatorSignature: ByteArray,
        val responderSignature: ByteArray,
        val initiatorConfirmation: ByteArray,
        val responderConfirmation: ByteArray,
        val sessionKeys: AdPairKeySchedule.Keys,
    )

    var state: State = State.INITIAL
        private set

    private var offer: AdPairOffer? = null
    private var response: AdPairOffer? = null
    private var challenge: AdPairChallenge? = null
    private var spake: Spake2PlusP256Session? = null
    private var shareP: ByteArray? = null
    private var shareV: ByteArray? = null
    private var confirmationP: ByteArray? = null
    private var confirmationV: ByteArray? = null
    private var responderSignature: ByteArray? = null

    fun startInitiator(
        mode: String,
        channelBinding: AdPairChannelBinding,
        expiresInMillis: Long = 60_000,
        endpointHint: String? = null,
        capabilities: List<String> = emptyList(),
    ): InitiatorStart {
        if (role != Role.INITIATOR) invalidState("only the initiator creates an offer")
        if (state != State.INITIAL) invalidState("pairing offer is not expected")
        if (expiresInMillis <= 0) {
            throw AdPairCoordinatorException(
                AdPairCoordinatorError.EXPIRED,
                "pairing offer lifetime must be positive",
            )
        }
        validateBinding(channelBinding)
        val nonce = Base64Url.encode(randomBytes(32))
        val created = AdPairOffer(
            type = AdPairOffer.TYPE_OFFER,
            deviceId = deviceId,
            publicKey = publicKey,
            nonce = nonce,
            expiresAt = now() + expiresInMillis,
            endpointHint = endpointHint,
            capabilities = capabilities,
            channelBinding = channelBinding,
        )
        validatePayload(created, AdPairOffer.TYPE_OFFER, null)
        val challenge = when (mode) {
            AdPairCodec.MODE_PIN -> AdPairCodec.createPinChallenge(created, now(), randomBytes)
            AdPairCodec.MODE_QR_SECRET -> AdPairCodec.createQrSecretChallenge(created, now(), randomBytes)
            else -> throw AdPairCodeException(
                AdPairCodeErrorCode.INVALID_MODE,
                "pairing code mode must be pin or qr-secret",
            )
        }
        offer = created
        this.challenge = challenge
        state = State.OFFER_CREATED
        return InitiatorStart(created, challenge)
    }

    fun joinResponder(
        code: String,
        pin: String? = null,
        expiresInMillis: Long = 60_000,
        endpointHint: String? = null,
        capabilities: List<String> = emptyList(),
    ): ResponderJoin {
        if (role != Role.RESPONDER) invalidState("only the responder scans a pairing code")
        if (state != State.INITIAL) invalidState("pairing code is not expected")
        val parsed = AdPairCodec.parse(code, now(), localDeviceId = deviceId)
        val parsedOffer = parsed.offer
        if (parsedOffer.deviceId == deviceId) {
            throw AdPairCoordinatorException(AdPairCoordinatorError.SELF_PAIRING, "self pairing")
        }
        assertNotRevoked(parsedOffer.deviceId)
        val remaining = parsedOffer.expiresAt - now()
        if (remaining <= 0) {
            throw AdPairCodeException(AdPairCodeErrorCode.EXPIRED_CODE, "pairing code has expired")
        }
        val responsePayload = AdPairOffer(
            type = AdPairOffer.TYPE_RESPONSE,
            deviceId = deviceId,
            publicKey = publicKey,
            nonce = Base64Url.encode(randomBytes(32)),
            replyTo = parsedOffer.nonce,
            expiresAt = now() + maxOf(1L, minOf(expiresInMillis, remaining)),
            endpointHint = endpointHint,
            capabilities = capabilities,
            channelBinding = parsedOffer.channelBinding,
        )
        validatePayload(responsePayload, AdPairOffer.TYPE_RESPONSE, null)
        if (responsePayload.channelBinding != parsedOffer.channelBinding) {
            throw AdPairCoordinatorException(
                AdPairCoordinatorError.BINDING_MISMATCH,
                "pairing channel binding mismatch",
            )
        }
        val registration = AdPairCodec.deriveRegistration(
            code = parsed,
            pin = pin,
            initiatorDeviceId = parsedOffer.deviceId,
            responderDeviceId = deviceId,
        )
        spake = Spake2PlusP256Session(
            role = Spake2PlusP256Session.Role.VERIFIER,
            context = AdPairTranscript.DOMAIN.toByteArray(Charsets.UTF_8),
            idProver = parsedOffer.deviceId.toByteArray(Charsets.UTF_8),
            idVerifier = deviceId.toByteArray(Charsets.UTF_8),
            w0 = registration.w0,
            L = registration.L,
        )
        offer = parsedOffer
        response = responsePayload
        challenge = null
        state = State.JOINED
        return ResponderJoin(
            offer = parsedOffer,
            response = responsePayload,
            responseData = PairingJson.strict.encodeToString(responsePayload).toByteArray(Charsets.UTF_8),
        )
    }

    fun acceptResponse(data: ByteArray): ByteArray {
        if (role != Role.INITIATOR) invalidState("only the initiator accepts a response")
        if (state != State.OFFER_CREATED) invalidState("pairing response is not expected")
        val localOffer = offer ?: invalidState("pairing offer is missing")
        val localChallenge = challenge ?: invalidState("pairing challenge is missing")
        val decoded = try {
            PairingJson.strict.decodeFromString<AdPairOffer>(data.toString(Charsets.UTF_8))
        } catch (error: Exception) {
            throw AdPairCoordinatorException(
                AdPairCoordinatorError.UNEXPECTED_TYPE,
                "pairing response is malformed",
            )
        }
        validatePayload(decoded, AdPairOffer.TYPE_RESPONSE, deviceId)
        if (decoded.deviceId == deviceId) {
            throw AdPairCoordinatorException(AdPairCoordinatorError.SELF_PAIRING, "self pairing")
        }
        assertNotRevoked(decoded.deviceId)
        if (decoded.replyTo != localOffer.nonce) {
            throw AdPairCoordinatorException(
                AdPairCoordinatorError.INVALID_REPLY_TO,
                "pairing response does not reply to this offer",
            )
        }
        if (decoded.channelBinding != localOffer.channelBinding) {
            throw AdPairCoordinatorException(
                AdPairCoordinatorError.BINDING_MISMATCH,
                "pairing channel binding mismatch",
            )
        }
        val registration = AdPairCodec.deriveRegistration(
            code = localChallenge.code,
            pin = localChallenge.pin,
            initiatorDeviceId = deviceId,
            responderDeviceId = decoded.deviceId,
        )
        val prover = Spake2PlusP256Session(
            role = Spake2PlusP256Session.Role.PROVER,
            context = AdPairTranscript.DOMAIN.toByteArray(Charsets.UTF_8),
            idProver = deviceId.toByteArray(Charsets.UTF_8),
            idVerifier = decoded.deviceId.toByteArray(Charsets.UTF_8),
            w0 = registration.w0,
            w1 = registration.w1,
        )
        val start = prover.proverStart()
        response = decoded
        spake = prover
        shareP = start
        state = State.AWAITING_VERIFIER_RESPONSE
        return start
    }

    fun respond(initiatorShare: ByteArray): ResponderResponse {
        if (role != Role.RESPONDER) invalidState("only the responder responds to a prover share")
        if (state != State.JOINED) invalidState("responder is not awaiting a prover share")
        val localOffer = offer ?: invalidState("pairing offer is missing")
        val localResponse = response ?: invalidState("pairing response is missing")
        val verifierSession = spake ?: invalidState("pairing session is missing")
        val reply = verifierSession.verifierRespond(initiatorShare)
        val confirmP = verifierSession.verifierConfirmationP()
        val evidence = AdPairPakeEvidence.fromBytes(
            initiatorShare = initiatorShare,
            responderShare = reply.first,
            initiatorConfirmation = confirmP,
            responderConfirmation = reply.second,
        )
        val transcript = AdPairTranscript.canonical(localOffer, localResponse, evidence)
        val signature = signer.sign(transcript)
        shareP = initiatorShare
        shareV = reply.first
        confirmationP = confirmP
        confirmationV = reply.second
        responderSignature = signature
        state = State.AWAITING_INITIATOR
        return ResponderResponse(reply.first, reply.second, signature)
    }

    fun finishInitiator(
        responderShare: ByteArray,
        responderConfirmation: ByteArray,
        responderSignature: ByteArray,
    ): Result {
        if (role != Role.INITIATOR) invalidState("only the initiator finishes the prover exchange")
        if (state != State.AWAITING_VERIFIER_RESPONSE) {
            invalidState("initiator is not awaiting a verifier response")
        }
        val localOffer = offer ?: invalidState("pairing offer is missing")
        val localResponse = response ?: invalidState("pairing response is missing")
        val prover = spake ?: invalidState("pairing session is missing")
        val localShareP = shareP ?: invalidState("prover share is missing")
        val finish = prover.proverFinish(responderShare, responderConfirmation)
        val evidence = AdPairPakeEvidence.fromBytes(
            initiatorShare = localShareP,
            responderShare = responderShare,
            initiatorConfirmation = finish.confirmation,
            responderConfirmation = finish.expectedConfirmation,
        )
        val transcript = AdPairTranscript.canonical(localOffer, localResponse, evidence)
        val transcriptHash = AdPairTranscript.hash(localOffer, localResponse, evidence)
        val signature = signer.sign(transcript)
        if (!verifier.verify(localResponse.publicKey, transcript, responderSignature)) {
            throw AdPairCoordinatorException(
                AdPairCoordinatorError.INVALID_SIGNATURE,
                "invalid responder transcript signature",
            )
        }
        assertNotRevoked(localResponse.deviceId)
        val keys = AdPairKeySchedule.derive(finish.keys.kShared, transcriptHash, localOffer.channelBinding)
        recordPeer(localResponse)
        state = State.COMPLETED
        return result(
            offer = localOffer,
            response = localResponse,
            transcript = transcript,
            transcriptHash = transcriptHash,
            initiatorSignature = signature,
            responderSignature = responderSignature,
            initiatorConfirmation = finish.confirmation,
            responderConfirmation = finish.expectedConfirmation,
            keys = keys,
        )
    }

    fun finishResponder(
        initiatorConfirmation: ByteArray,
        initiatorSignature: ByteArray,
    ): Result {
        if (role != Role.RESPONDER) invalidState("only the responder finishes the verifier exchange")
        if (state != State.AWAITING_INITIATOR) {
            invalidState("responder is not awaiting an initiator confirmation")
        }
        val localOffer = offer ?: invalidState("pairing offer is missing")
        val localResponse = response ?: invalidState("pairing response is missing")
        val verifierSession = spake ?: invalidState("pairing session is missing")
        val localShareP = shareP ?: invalidState("prover share is missing")
        val localShareV = shareV ?: invalidState("verifier share is missing")
        val localResponderSignature = responderSignature ?: invalidState("responder signature is missing")
        val finish = verifierSession.verifierFinish(initiatorConfirmation)
        val evidence = AdPairPakeEvidence.fromBytes(
            initiatorShare = localShareP,
            responderShare = localShareV,
            initiatorConfirmation = initiatorConfirmation,
            responderConfirmation = finish.expectedConfirmation,
        )
        val transcript = AdPairTranscript.canonical(localOffer, localResponse, evidence)
        val transcriptHash = AdPairTranscript.hash(localOffer, localResponse, evidence)
        if (!verifier.verify(localOffer.publicKey, transcript, initiatorSignature)) {
            throw AdPairCoordinatorException(
                AdPairCoordinatorError.INVALID_SIGNATURE,
                "invalid initiator transcript signature",
            )
        }
        assertNotRevoked(localOffer.deviceId)
        val keys = AdPairKeySchedule.derive(finish.keys.kShared, transcriptHash, localOffer.channelBinding)
        recordPeer(localOffer)
        state = State.COMPLETED
        return result(
            offer = localOffer,
            response = localResponse,
            transcript = transcript,
            transcriptHash = transcriptHash,
            initiatorSignature = initiatorSignature,
            responderSignature = localResponderSignature,
            initiatorConfirmation = initiatorConfirmation,
            responderConfirmation = finish.expectedConfirmation,
            keys = keys,
        )
    }

    private fun result(
        offer: AdPairOffer,
        response: AdPairOffer,
        transcript: ByteArray,
        transcriptHash: ByteArray,
        initiatorSignature: ByteArray,
        responderSignature: ByteArray,
        initiatorConfirmation: ByteArray,
        responderConfirmation: ByteArray,
        keys: AdPairKeySchedule.Keys,
    ): Result = Result(
        offer = offer,
        response = response,
        transcript = transcript,
        transcriptHash = transcriptHash,
        shortAuthenticationString = AdPairTranscript.shortAuthenticationString(transcriptHash),
        channelBinding = offer.channelBinding,
        capabilities = (offer.capabilities + response.capabilities).distinct().sorted(),
        initiatorSignature = initiatorSignature,
        responderSignature = responderSignature,
        initiatorConfirmation = initiatorConfirmation,
        responderConfirmation = responderConfirmation,
        sessionKeys = keys,
    )

    private fun recordPeer(payload: AdPairOffer) {
        val store = registry ?: return
        store.upsert(
            PeerRecord(
                deviceId = payload.deviceId,
                publicKey = payload.publicKey,
                displayName = peerDisplayLabel?.trim()?.takeIf { it.isNotEmpty() }
                    ?: "Peer " + payload.deviceId.removePrefix(DeviceId.PREFIX).take(12),
                pairedAtEpochSeconds = now() / 1000,
                capabilities = payload.capabilities,
                trusted = store.find(payload.deviceId)?.trusted == true,
            ),
        )
    }

    fun trustPeer(deviceId: String): Boolean = registry?.trust(deviceId) == true

    private fun assertNotRevoked(peerDeviceId: String) {
        if (registry?.find(peerDeviceId)?.revoked == true) {
            throw AdPairCoordinatorException(
                AdPairCoordinatorError.REVOKED_DEVICE,
                "the pairing device has been revoked",
            )
        }
    }

    private fun validatePayload(payload: AdPairOffer, expectedType: String, localDeviceId: String?) {
        if (payload.protocol != AdPairOffer.PROTOCOL) {
            throw AdPairCoordinatorException(
                AdPairCoordinatorError.UNSUPPORTED_PROTOCOL,
                "unsupported pairing protocol",
            )
        }
        if (payload.version != AdPairOffer.VERSION) {
            throw AdPairCoordinatorException(
                AdPairCoordinatorError.UNSUPPORTED_VERSION,
                "unsupported pairing version",
            )
        }
        if (payload.type != expectedType) {
            throw AdPairCoordinatorException(
                AdPairCoordinatorError.UNEXPECTED_TYPE,
                "unexpected pairing payload type",
            )
        }
        if (!DeviceId.isValid(payload.deviceId)) {
            throw AdPairCoordinatorException(AdPairCoordinatorError.INVALID_DEVICE_ID, "invalid pairing device ID")
        }
        if (localDeviceId != null && payload.deviceId == localDeviceId) {
            throw AdPairCoordinatorException(AdPairCoordinatorError.SELF_PAIRING, "self pairing")
        }
        val spki = try {
            Base64Url.decode(payload.publicKey)
        } catch (error: Exception) {
            throw AdPairCoordinatorException(AdPairCoordinatorError.INVALID_PUBLIC_KEY, "invalid pairing public key")
        }
        try {
            val publicKey = KeyFactory.getInstance("EC")
                .generatePublic(X509EncodedKeySpec(spki)) as? ECPublicKey
                ?: throw IllegalArgumentException("not EC")
            if (publicKey.params.curve.field.fieldSize != 256) {
                throw IllegalArgumentException("not P-256")
            }
        } catch (error: Exception) {
            throw AdPairCoordinatorException(AdPairCoordinatorError.INVALID_PUBLIC_KEY, "invalid pairing public key")
        }
        if (DeviceId.fromSpki(spki) != payload.deviceId) {
            throw AdPairCoordinatorException(
                AdPairCoordinatorError.INVALID_DEVICE_ID,
                "pairing device ID does not match its public key",
            )
        }
        val nonce = try {
            Base64Url.decode(payload.nonce)
        } catch (error: Exception) {
            throw AdPairCoordinatorException(AdPairCoordinatorError.INVALID_NONCE, "invalid pairing nonce")
        }
        if (nonce.size !in 16..128) {
            throw AdPairCoordinatorException(AdPairCoordinatorError.INVALID_NONCE, "invalid pairing nonce")
        }
        if (expectedType == AdPairOffer.TYPE_OFFER) {
            if (payload.replyTo != null) {
                throw AdPairCoordinatorException(AdPairCoordinatorError.INVALID_REPLY_TO, "offer must not reply to a nonce")
            }
        } else {
            val replyTo = payload.replyTo?.let {
                try {
                    Base64Url.decode(it)
                } catch (error: Exception) {
                    null
                }
            }
            if (replyTo == null || replyTo.size !in 16..128) {
                throw AdPairCoordinatorException(AdPairCoordinatorError.INVALID_REPLY_TO, "invalid pairing reply-to nonce")
            }
        }
        if (payload.expiresAt <= now()) {
            throw AdPairCoordinatorException(AdPairCoordinatorError.EXPIRED, "pairing payload has expired")
        }
        validateHint(payload.endpointHint)
        validateHint(payload.relayHint)
        if (payload.capabilities.size > 64 ||
            payload.capabilities.any { it.isEmpty() || it.length > 128 } ||
            payload.capabilities.toSet().size != payload.capabilities.size
        ) {
            throw AdPairCoordinatorException(
                AdPairCoordinatorError.INVALID_CAPABILITIES,
                "invalid pairing capabilities",
            )
        }
        validateBinding(payload.channelBinding)
    }

    private fun validateHint(value: String?) {
        if (value != null && (value.isEmpty() || value.length > 2048)) {
            throw AdPairCoordinatorException(AdPairCoordinatorError.INVALID_HINT, "invalid pairing hint")
        }
    }

    private fun validateBinding(binding: AdPairChannelBinding) {
        val valid = when (binding.kind) {
            "certificate-hash" -> Regex("^[0-9a-fA-F]{64}$").matches(binding.value)
            "exporter" -> try {
                Base64Url.decode(binding.value).size >= 16
            } catch (error: Exception) {
                false
            }
            "iroh-endpoint" -> binding.value.isNotEmpty() &&
                binding.value.length <= 256 &&
                binding.value == binding.value.trim()
            else -> false
        }
        if (!valid) {
            throw AdPairCoordinatorException(AdPairCoordinatorError.INVALID_BINDING, "invalid pairing channel binding")
        }
    }

    private fun invalidState(message: String): Nothing =
        throw AdPairCoordinatorException(AdPairCoordinatorError.INVALID_STATE, message)
}
