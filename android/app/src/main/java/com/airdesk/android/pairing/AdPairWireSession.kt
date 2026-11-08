package com.airdesk.android.pairing

class AdPairWireSession(
    val role: Role,
    private val coordinator: AdPairCoordinator,
) {
    enum class Role {
        HOST,
        CONTROLLER,
    }

    enum class State {
        IDLE,
        WAITING_FOR_CONTROLLER,
        AWAITING_SHARE,
        AWAITING_VERIFIER_RESPONSE,
        AWAITING_INITIATOR_FINISH,
        AWAITING_USER_VERIFICATION,
        COMPLETED,
        FAILED,
    }

    var state: State = State.IDLE
        private set

    var code: String? = null
        private set

    var pin: String? = null
        private set

    var shortAuthenticationString: String? = null
        private set

    var peerDeviceId: String? = null
        private set

    var lastError: String? = null
        private set

    private var result: AdPairCoordinator.Result? = null

    fun startHost(
        mode: String,
        channelBinding: AdPairChannelBinding,
        expiresInMillis: Long = 60_000,
        endpointHint: String? = null,
        capabilities: List<String> = emptyList(),
    ): AdPairChallenge {
        requireSession(role == Role.HOST) { "only the host starts a pairing code" }
        requireSession(state == State.IDLE) { "pairing session is not idle" }
        return try {
            val start = coordinator.startInitiator(
                mode = mode,
                channelBinding = channelBinding,
                expiresInMillis = expiresInMillis,
                endpointHint = endpointHint,
                capabilities = capabilities,
            )
            code = start.challenge.serialized
            pin = start.challenge.pin
            state = State.WAITING_FOR_CONTROLLER
            start.challenge
        } catch (error: Exception) {
            fail(error)
            throw error
        }
    }

    fun join(
        code: String,
        pin: String? = null,
        expiresInMillis: Long = 60_000,
        endpointHint: String? = null,
        capabilities: List<String> = emptyList(),
    ): ByteArray {
        requireSession(role == Role.CONTROLLER) { "only the controller joins a pairing code" }
        requireSession(state == State.IDLE) { "pairing session is not idle" }
        return try {
            val joined = coordinator.joinResponder(
                code = code,
                pin = pin,
                expiresInMillis = expiresInMillis,
                endpointHint = endpointHint,
                capabilities = capabilities,
            )
            this.code = code
            this.pin = pin
            peerDeviceId = joined.offer.deviceId
            state = State.AWAITING_SHARE
            PairingWire.encode(PairingWire.response(joined.responseData))
        } catch (error: Exception) {
            fail(error)
            throw error
        }
    }

    fun receive(data: ByteArray): ByteArray? {
        if (state == State.FAILED || state == State.COMPLETED) return null
        return try {
            val message = PairingWire.decode(data)
            when {
                role == Role.HOST && message.kind == PairingWire.Kind.RESPONSE -> {
                    requireSession(state == State.WAITING_FOR_CONTROLLER) { "host is not waiting for a response" }
                    val payload = message.response ?: invalidState("host response payload is missing")
                    val share = coordinator.acceptResponse(payload)
                    state = State.AWAITING_VERIFIER_RESPONSE
                    PairingWire.encode(PairingWire.share(share))
                }
                role == Role.CONTROLLER && message.kind == PairingWire.Kind.SHARE -> {
                    requireSession(state == State.AWAITING_SHARE) { "controller is not awaiting a share" }
                    val share = message.share ?: invalidState("controller share payload is missing")
                    val response = coordinator.respond(share)
                    state = State.AWAITING_INITIATOR_FINISH
                    PairingWire.encode(
                        PairingWire.verifierResponse(
                            response.share,
                            response.confirmation,
                            response.signature,
                        ),
                    )
                }
                role == Role.HOST && message.kind == PairingWire.Kind.VERIFIER_RESPONSE -> {
                    requireSession(state == State.AWAITING_VERIFIER_RESPONSE) {
                        "host is not awaiting a verifier response"
                    }
                    val share = message.share ?: invalidState("verifier share payload is missing")
                    val confirmation = message.confirmation ?: invalidState("verifier confirmation is missing")
                    val signature = message.signature ?: invalidState("verifier signature is missing")
                    val completion = coordinator.finishInitiator(share, confirmation, signature)
                    complete(completion)
                    PairingWire.encode(
                        PairingWire.initiatorFinish(
                            completion.initiatorConfirmation,
                            completion.initiatorSignature,
                        ),
                    )
                }
                role == Role.CONTROLLER && message.kind == PairingWire.Kind.INITIATOR_FINISH -> {
                    requireSession(state == State.AWAITING_INITIATOR_FINISH) {
                        "controller is not awaiting an initiator finish"
                    }
                    val confirmation = message.confirmation ?: invalidState("initiator confirmation is missing")
                    val signature = message.signature ?: invalidState("initiator signature is missing")
                    val completion = coordinator.finishResponder(confirmation, signature)
                    complete(completion)
                    PairingWire.encode(
                        PairingWire.responderFinish(
                            completion.responderConfirmation,
                            completion.responderSignature,
                        ),
                    )
                }
                role == Role.HOST && message.kind == PairingWire.Kind.RESPONDER_FINISH -> null
                else -> invalidState("unexpected pairing wire message")
            }
        } catch (error: Exception) {
            fail(error)
            throw error
        }
    }

    fun confirmShortAuthenticationString(entered: String): AdPairKeySchedule.Keys {
        requireSession(state == State.AWAITING_USER_VERIFICATION) {
            "pairing is not awaiting SAS confirmation"
        }
        val expected = shortAuthenticationString ?: invalidState("pairing SAS is missing")
        if (entered.trim() != expected) {
            fail(AdPairWireException("pairing verification code does not match"))
            throw AdPairWireException("pairing verification code does not match")
        }
        peerDeviceId?.let { coordinator.trustPeer(it) }
        state = State.COMPLETED
        return result?.sessionKeys ?: invalidState("pairing result is missing")
    }

    fun reset() {
        state = State.IDLE
        code = null
        pin = null
        shortAuthenticationString = null
        peerDeviceId = null
        lastError = null
        result = null
    }

    private fun complete(completion: AdPairCoordinator.Result) {
        result = completion
        shortAuthenticationString = completion.shortAuthenticationString
        peerDeviceId = if (role == Role.HOST) {
            completion.response.deviceId
        } else {
            completion.offer.deviceId
        }
        state = State.AWAITING_USER_VERIFICATION
    }

    private fun fail(error: Exception) {
        lastError = error.message ?: error.javaClass.simpleName
        state = State.FAILED
    }

    private inline fun requireSession(condition: Boolean, message: () -> String) {
        if (!condition) throw invalidState(message())
    }

    private fun invalidState(message: String): Nothing = throw AdPairWireException(message)
}

class AdPairWireException(message: String) : IllegalStateException(message)
