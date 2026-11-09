package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceIdentityStore
import com.airdesk.android.util.Base64Url
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import org.bouncycastle.asn1.ASN1Integer
import org.bouncycastle.asn1.ASN1Sequence
import org.bouncycastle.asn1.DERSequence

class AndroidAdPairSigner(
    private val store: DeviceIdentityStore,
) : AdPairSigner {
    override fun sign(data: ByteArray): ByteArray {
        val privateKey = KeyStore.getInstance(KEYSTORE).apply { load(null) }
            .getKey(DeviceIdentityStore.ALIAS, null) as? PrivateKey
            ?: error("AirDesk identity private key is missing")
        val der = Signature.getInstance("SHA256withECDSA").run {
            initSign(privateKey)
            update(data)
            sign()
        }
        return EcdsaSignatureFormat.derToRaw(der)
    }

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
    }
}

class AndroidAdPairVerifier : AdPairSignatureVerifier {
    override fun verify(publicKeyBase64Url: String, data: ByteArray, signature: ByteArray): Boolean {
        if (signature.size != EcdsaSignatureFormat.RAW_LENGTH) return false
        return runCatching {
            val spki = Base64Url.decode(publicKeyBase64Url)
            val publicKey = KeyFactory.getInstance("EC")
                .generatePublic(X509EncodedKeySpec(spki))
            Signature.getInstance("SHA256withECDSA").run {
                initVerify(publicKey)
                update(data)
                verify(EcdsaSignatureFormat.rawToDer(signature))
            }
        }.getOrDefault(false)
    }
}

object EcdsaSignatureFormat {
    const val RAW_LENGTH = 64

    fun derToRaw(der: ByteArray): ByteArray {
        val sequence = ASN1Sequence.getInstance(der)
        require(sequence.size() == 2) { "ECDSA signature must contain r and s" }
        val r = (sequence.getObjectAt(0) as ASN1Integer).value
        val s = (sequence.getObjectAt(1) as ASN1Integer).value
        return fixedWidth(r) + fixedWidth(s)
    }

    fun rawToDer(raw: ByteArray): ByteArray {
        require(raw.size == RAW_LENGTH) { "ECDSA raw signature must be 64 bytes" }
        val r = BigInteger(1, raw.copyOfRange(0, 32))
        val s = BigInteger(1, raw.copyOfRange(32, 64))
        return DERSequence(arrayOf(ASN1Integer(r), ASN1Integer(s))).encoded
    }

    private fun fixedWidth(value: BigInteger): ByteArray {
        val bytes = value.toByteArray()
        val unsigned = if (bytes.size > 32 && bytes[0] == 0.toByte()) bytes.copyOfRange(1, bytes.size) else bytes
        require(unsigned.size <= 32) { "ECDSA signature integer is too large" }
        return ByteArray(32 - unsigned.size) + unsigned
    }
}
