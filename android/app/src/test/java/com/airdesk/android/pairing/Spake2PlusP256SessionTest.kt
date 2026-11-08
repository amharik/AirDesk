package com.airdesk.android.pairing

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class Spake2PlusP256SessionTest {
    private val context = "SPAKE2+-P256-SHA256-HKDF-SHA256-HMAC-SHA256 Test Vectors".toByteArray()
    private val idProver = "client".toByteArray()
    private val idVerifier = "server".toByteArray()
    private val w0 = hex("bb8e1bbcf3c48f62c08db243652ae55d3e5586053fca77102994f23ad95491b3")
    private val w1 = hex("7e945f34d78785b8a3ef44d0df5a1a97d6b3b460409a345ca7830387a74b1dba")
    private val L = hex("04eb7c9db3d9a9eb1f8adab81b5794c1f13ae3e225efbe91ea487425854c7fc00f00bfedcbd09b2400142d40a14f2064ef31dfaa903b91d1faea7093d835966efd")
    private val x = hex("d1232c8e8693d02368976c174e2088851b8365d0d79a9eee709c6a05a2fad539")
    private val y = hex("717a72348a182085109c8d3917d6c43d59b224dc6a7fc4f0483232fa6516d8b3")
    private val shareP = hex("04ef3bd051bf78a2234ec0df197f7828060fe9856503579bb1733009042c15c0c1de127727f418b5966afadfdd95a6e4591d171056b333dab97a79c7193e341727")
    private val confirmP = hex("926cc713504b9b4d76c9162ded04b5493e89109f6d89462cd33adc46fda27527")
    private val confirmV = hex("9747bcc4f8fe9f63defee53ac9b07876d907d55047e6ff2def2e7529089d3e68")

    @Test
    fun runsProverVerifierStateMachine() {
        val prover = session(Spake2PlusP256Session.Role.PROVER, w1 = w1)
        val verifier = session(Spake2PlusP256Session.Role.VERIFIER, L = L)

        assertArrayEquals(shareP, prover.proverStart())
        val verifierResponse = verifier.verifierRespond(shareP)
        assertArrayEquals(confirmV, verifierResponse.second)
        val proverResult = prover.proverFinish(verifierResponse.first, verifierResponse.second)
        assertArrayEquals(confirmP, proverResult.confirmation)
        assertEquals(Spake2PlusP256Session.Phase.COMPLETED, prover.phase)

        assertArrayEquals(confirmP, verifier.verifierConfirmationP())
        val verifierResult = verifier.verifierFinish(proverResult.confirmation)
        assertArrayEquals(proverResult.keys.kShared, verifierResult.keys.kShared)
        assertArrayEquals(proverResult.transcript, verifierResult.transcript)
        assertEquals(Spake2PlusP256Session.Phase.COMPLETED, verifier.phase)
    }

    @Test
    fun rejectsOutOfOrderCallsAndBadConfirmation() {
        val prover = session(Spake2PlusP256Session.Role.PROVER, w1 = w1)
        val verifier = session(Spake2PlusP256Session.Role.VERIFIER, L = L)
        expectCode(Spake2PlusP256.ErrorCode.INVALID_STATE) { verifier.proverStart() }
        expectCode(Spake2PlusP256.ErrorCode.INVALID_STATE) { prover.verifierRespond(shareP) }

        prover.proverStart()
        val verifierResponse = verifier.verifierRespond(shareP)
        expectCode(Spake2PlusP256.ErrorCode.CONFIRMATION_MISMATCH) {
            prover.proverFinish(verifierResponse.first, ByteArray(32) { 1 })
        }
        expectCode(Spake2PlusP256.ErrorCode.CONFIRMATION_MISMATCH) {
            verifier.verifierFinish(ByteArray(32) { 1 })
        }
    }

    private fun session(
        role: Spake2PlusP256Session.Role,
        w1: ByteArray? = null,
        L: ByteArray? = null,
    ) = Spake2PlusP256Session(
        role = role,
        context = context,
        idProver = idProver,
        idVerifier = idVerifier,
        w0 = w0,
        w1 = w1,
        L = L,
        x = if (role == Spake2PlusP256Session.Role.PROVER) x else null,
        y = if (role == Spake2PlusP256Session.Role.VERIFIER) y else null,
    )

    private fun expectCode(code: Spake2PlusP256.ErrorCode, block: () -> Unit) {
        try {
            block()
            fail("expected ${code.name}")
        } catch (error: Spake2PlusP256.Spake2PlusException) {
            assertEquals(code, error.code)
        }
    }

    private fun hex(value: String): ByteArray =
        ByteArray(value.length / 2) { index ->
            value.substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
}
