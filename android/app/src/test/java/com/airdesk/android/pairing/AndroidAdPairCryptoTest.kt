package com.airdesk.android.pairing

import com.airdesk.android.util.Base64Url
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidAdPairCryptoTest {
    @Test
    fun convertsDerAndRawEcdsaSignaturesBothWays() {
        val keyPair = KeyPairGenerator.getInstance("EC").apply {
            initialize(ECGenParameterSpec("secp256r1"))
        }.generateKeyPair()
        val data = "AD-PAIR-1 transcript".toByteArray()
        val der = Signature.getInstance("SHA256withECDSA").run {
            initSign(keyPair.private)
            update(data)
            sign()
        }
        val raw = EcdsaSignatureFormat.derToRaw(der)
        assertArrayEquals(der, EcdsaSignatureFormat.rawToDer(raw))

        val publicKey = Base64Url.encode(keyPair.public.encoded)
        val verifier = AndroidAdPairVerifier()
        assertTrue(verifier.verify(publicKey, data, raw))
        assertFalse(verifier.verify(publicKey, data + 1, raw))
        assertFalse(verifier.verify(publicKey, data, raw.copyOf(raw.size - 1)))
    }
}
