package com.airdesk.android.pairing

class Spake2PlusP256Session(
    val role: Role,
    private val context: ByteArray,
    private val idProver: ByteArray,
    private val idVerifier: ByteArray,
    private val w0: ByteArray,
    private val w1: ByteArray? = null,
    private val L: ByteArray? = null,
    private val x: ByteArray? = null,
    private val y: ByteArray? = null,
) {
    enum class Role {
        PROVER,
        VERIFIER,
    }

    enum class Phase {
        INITIAL,
        AWAITING_SHARE,
        AWAITING_CONFIRMATION,
        COMPLETED,
    }

    data class Result(
        val transcript: ByteArray,
        val keys: Spake2PlusP256.Keys,
        val confirmation: ByteArray,
        val expectedConfirmation: ByteArray,
    ) {
        override fun equals(other: Any?): Boolean =
            other is Result &&
                transcript.contentEquals(other.transcript) &&
                keys == other.keys &&
                confirmation.contentEquals(other.confirmation) &&
                expectedConfirmation.contentEquals(other.expectedConfirmation)

        override fun hashCode(): Int = listOf(
            transcript.contentHashCode(),
            keys.hashCode(),
            confirmation.contentHashCode(),
            expectedConfirmation.contentHashCode(),
        ).hashCode()
    }

    var phase: Phase = Phase.INITIAL
        private set

    private var proverInit: Spake2PlusP256.ProverInit? = null
    private var verifierPending: Spake2PlusP256.VerifierFinish? = null

    fun proverStart(): ByteArray {
        if (role != Role.PROVER) invalidState("only the prover starts the exchange")
        if (phase != Phase.INITIAL) invalidState("prover exchange already started")
        val start = Spake2PlusP256.proverInit(w0, x)
        proverInit = start
        phase = Phase.AWAITING_SHARE
        return start.shareP
    }

    fun verifierRespond(shareP: ByteArray): Pair<ByteArray, ByteArray> {
        if (role != Role.VERIFIER) invalidState("only the verifier responds to a prover share")
        if (phase != Phase.INITIAL) invalidState("verifier response already produced")
        val registration = L ?: invalidInput("verifier registration record L is required")
        val result = Spake2PlusP256.verifierFinish(
            w0 = w0,
            L = registration,
            shareP = shareP,
            context = context,
            idProver = idProver,
            idVerifier = idVerifier,
            y = y,
        )
        verifierPending = result
        phase = Phase.AWAITING_CONFIRMATION
        return result.finish.shareV to result.finish.confirmation
    }

    fun proverFinish(shareV: ByteArray, confirmationV: ByteArray): Result {
        if (role != Role.PROVER) invalidState("only the prover finishes with a verifier response")
        val start = proverInit
        if (phase != Phase.AWAITING_SHARE || start == null) {
            invalidState("prover is not awaiting a verifier share")
        }
        val witness = w1 ?: invalidInput("prover witness w1 is required")
        val finish = Spake2PlusP256.proverFinish(
            w0 = w0,
            w1 = witness,
            x = start.x,
            shareV = shareV,
            context = context,
            idProver = idProver,
            idVerifier = idVerifier,
        )
        Spake2PlusP256.assertConfirmation(finish.expectedConfirmation, confirmationV)
        phase = Phase.COMPLETED
        return Result(
            transcript = finish.transcript,
            keys = finish.keys,
            confirmation = finish.confirmation,
            expectedConfirmation = finish.expectedConfirmation,
        )
    }

    fun verifierConfirmationP(): ByteArray {
        if (role != Role.VERIFIER) invalidState("only the verifier has a prover confirmation")
        val pending = verifierPending
        if (phase != Phase.AWAITING_CONFIRMATION || pending == null) {
            invalidState("verifier has not responded")
        }
        return pending.finish.expectedConfirmation
    }

    fun verifierFinish(confirmationP: ByteArray): Result {
        if (role != Role.VERIFIER) invalidState("only the verifier finishes with a prover confirmation")
        val pending = verifierPending
        if (phase != Phase.AWAITING_CONFIRMATION || pending == null) {
            invalidState("verifier is not awaiting a prover confirmation")
        }
        Spake2PlusP256.assertConfirmation(pending.finish.expectedConfirmation, confirmationP)
        phase = Phase.COMPLETED
        return Result(
            transcript = pending.finish.transcript,
            keys = pending.finish.keys,
            confirmation = pending.finish.expectedConfirmation,
            expectedConfirmation = pending.finish.confirmation,
        )
    }

    private fun invalidState(message: String): Nothing =
        throw Spake2PlusP256.Spake2PlusException(Spake2PlusP256.ErrorCode.INVALID_STATE, message)

    private fun invalidInput(message: String): Nothing =
        throw Spake2PlusP256.Spake2PlusException(Spake2PlusP256.ErrorCode.INVALID_INPUT, message)
}
