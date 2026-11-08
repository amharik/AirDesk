package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class Spake2PlusP256Test {
    private val context = "SPAKE2+-P256-SHA256-HKDF-SHA256-HMAC-SHA256 Test Vectors".toByteArray()
    private val idProver = "client".toByteArray()
    private val idVerifier = "server".toByteArray()
    private val w0 = hex("bb8e1bbcf3c48f62c08db243652ae55d3e5586053fca77102994f23ad95491b3")
    private val w1 = hex("7e945f34d78785b8a3ef44d0df5a1a97d6b3b460409a345ca7830387a74b1dba")
    private val L = hex("04eb7c9db3d9a9eb1f8adab81b5794c1f13ae3e225efbe91ea487425854c7fc00f00bfedcbd09b2400142d40a14f2064ef31dfaa903b91d1faea7093d835966efd")
    private val x = hex("d1232c8e8693d02368976c174e2088851b8365d0d79a9eee709c6a05a2fad539")
    private val shareP = hex("04ef3bd051bf78a2234ec0df197f7828060fe9856503579bb1733009042c15c0c1de127727f418b5966afadfdd95a6e4591d171056b333dab97a79c7193e341727")
    private val y = hex("717a72348a182085109c8d3917d6c43d59b224dc6a7fc4f0483232fa6516d8b3")
    private val shareV = hex("04c0f65da0d11927bdf5d560c69e1d7d939a05b0e88291887d679fcadea75810fb5cc1ca7494db39e82ff2f50665255d76173e09986ab46742c798a9a68437b048")
    private val zVector = hex("04bbfce7dd7f277819c8da21544afb7964705569bdf12fb92aa388059408d50091a0c5f1d3127f56813b5337f9e4e67e2ca633117a4fbd559946ab474356c41839")
    private val vVector = hex("0458bf27c6bca011c9ce1930e8984a797a3419797b936629a5a937cf2f11c8b9514b82b993da8a46e664f23db7c01edc87faa530db01c2ee405230b18997f16b68")
    private val transcriptVector = hex("38000000000000005350414b45322b2d503235362d5348413235362d484b44462d5348413235362d484d41432d534841323536205465737420566563746f72730600000000000000636c69656e740600000000000000736572766572410000000000000004886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f5ff355163e43ce224e0b0e65ff02ac8e5c7be09419c785e0ca547d55a12e2d20410000000000000004d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b4907d60aa6bfade45008a636337f5168c64d9bd36034808cd564490b1e656edbe7410000000000000004ef3bd051bf78a2234ec0df197f7828060fe9856503579bb1733009042c15c0c1de127727f418b5966afadfdd95a6e4591d171056b333dab97a79c7193e341727410000000000000004c0f65da0d11927bdf5d560c69e1d7d939a05b0e88291887d679fcadea75810fb5cc1ca7494db39e82ff2f50665255d76173e09986ab46742c798a9a68437b048410000000000000004bbfce7dd7f277819c8da21544afb7964705569bdf12fb92aa388059408d50091a0c5f1d3127f56813b5337f9e4e67e2ca633117a4fbd559946ab474356c4183941000000000000000458bf27c6bca011c9ce1930e8984a797a3419797b936629a5a937cf2f11c8b9514b82b993da8a46e664f23db7c01edc87faa530db01c2ee405230b18997f16b682000000000000000bb8e1bbcf3c48f62c08db243652ae55d3e5586053fca77102994f23ad95491b3")
    private val kMainVector = hex("4c59e1ccf2cfb961aa31bd9434478a1089b56cd11542f53d3576fb6c2a438a29")
    private val kConfirmPVector = hex("871ae3f7b78445e34438fb284504240239031c39d80ac23eb5ab9be5ad6db58a")
    private val kConfirmVVector = hex("ccd53c7c1fa37b64a462b40db8be101cedcf838950162902054e644b400f1680")
    private val confirmPVector = hex("926cc713504b9b4d76c9162ded04b5493e89109f6d89462cd33adc46fda27527")
    private val confirmVVector = hex("9747bcc4f8fe9f63defee53ac9b07876d907d55047e6ff2def2e7529089d3e68")
    private val kSharedVector = hex("0c5f8ccd1413423a54f6c1fb26ff01534a87f893779c6e68666d772bfd91f3e7")

    @Test
    fun proverAndVerifierMatchRfcVector() {
        val init = Spake2PlusP256.proverInit(w0, x)
        assertArrayEquals(shareP, init.shareP)

        val verifier = Spake2PlusP256.verifierFinish(
            w0 = w0,
            L = L,
            shareP = init.shareP,
            context = context,
            idProver = idProver,
            idVerifier = idVerifier,
            y = y,
        )
        assertArrayEquals(shareV, verifier.finish.shareV)
        assertArrayEquals(zVector, verifier.finish.z)
        assertArrayEquals(vVector, verifier.finish.v)
        assertArrayEquals(transcriptVector, verifier.finish.transcript)
        assertArrayEquals(kMainVector, verifier.finish.keys.kMain)
        assertArrayEquals(kConfirmPVector, verifier.finish.keys.kConfirmP)
        assertArrayEquals(kConfirmVVector, verifier.finish.keys.kConfirmV)
        assertArrayEquals(kSharedVector, verifier.finish.keys.kShared)
        assertArrayEquals(confirmVVector, verifier.finish.confirmation)
        assertArrayEquals(confirmPVector, verifier.finish.expectedConfirmation)

        val prover = Spake2PlusP256.proverFinish(
            w0 = w0,
            w1 = w1,
            x = init.x,
            shareV = verifier.finish.shareV,
            context = context,
            idProver = idProver,
            idVerifier = idVerifier,
        )
        assertArrayEquals(zVector, prover.z)
        assertArrayEquals(vVector, prover.v)
        assertArrayEquals(transcriptVector, prover.transcript)
        assertArrayEquals(kMainVector, prover.keys.kMain)
        assertArrayEquals(kConfirmPVector, prover.keys.kConfirmP)
        assertArrayEquals(kConfirmVVector, prover.keys.kConfirmV)
        assertArrayEquals(kSharedVector, prover.keys.kShared)
        assertArrayEquals(confirmPVector, prover.confirmation)
        assertArrayEquals(confirmVVector, prover.expectedConfirmation)

        Spake2PlusP256.assertConfirmation(prover.expectedConfirmation, verifier.finish.confirmation)
        Spake2PlusP256.assertConfirmation(verifier.finish.expectedConfirmation, prover.confirmation)
    }

    @Test
    fun rejectsInvalidPointsAndScalars() {
        expectCode(Spake2PlusP256.ErrorCode.INVALID_LENGTH) {
            Spake2PlusP256.proverInit(ByteArray(31))
        }
        expectCode(Spake2PlusP256.ErrorCode.INVALID_SCALAR) {
            Spake2PlusP256.proverInit(w0, ByteArray(32))
        }
        expectCode(Spake2PlusP256.ErrorCode.INVALID_LENGTH) {
            Spake2PlusP256.verifierFinish(
                w0 = w0,
                L = L,
                shareP = ByteArray(64),
                context = context,
                idProver = idProver,
                idVerifier = idVerifier,
                y = y,
            )
        }
        expectCode(Spake2PlusP256.ErrorCode.IDENTITY_POINT) {
            Spake2PlusP256.verifierFinish(
                w0 = w0,
                L = L,
                shareP = byteArrayOf(0),
                context = context,
                idProver = idProver,
                idVerifier = idVerifier,
                y = y,
            )
        }
        expectCode(Spake2PlusP256.ErrorCode.CONFIRMATION_MISMATCH) {
            Spake2PlusP256.assertConfirmation(ByteArray(32), ByteArray(32) { 1 })
        }
    }

    @Test
    fun transcriptUsesCrossPlatformVector() {
        val actual = Spake2PlusP256.transcript(
            context = context,
            idProver = idProver,
            idVerifier = idVerifier,
            shareP = shareP,
            shareV = shareV,
            z = zVector,
            v = vVector,
            w0 = w0,
        )
        assertArrayEquals(transcriptVector, actual)
        assertEquals(DeviceId.hexLowercase(kMainVector), DeviceId.hexLowercase(Spake2PlusP256.deriveKeys(actual).kMain))
    }

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
