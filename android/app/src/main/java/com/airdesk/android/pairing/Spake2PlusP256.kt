package com.airdesk.android.pairing

import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import org.bouncycastle.asn1.x9.ECNamedCurveTable
import org.bouncycastle.math.ec.ECPoint

object Spake2PlusP256 {
    const val SUITE = "SPAKE2+-P256-SHA256-HKDF-SHA256-HMAC-SHA256"
    const val M_COMPRESSED_HEX = "02886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f"
    const val N_COMPRESSED_HEX = "03d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b49"
    const val SCALAR_BYTES = 32
    const val CONFIRMATION_BYTES = 32

    private val parameters = ECNamedCurveTable.getByName("secp256r1")
    private val curve = parameters.curve
    private val order = parameters.n
    private val base = parameters.g
    private val mPoint = curve.decodePoint(hexToBytes(M_COMPRESSED_HEX)).normalize()
    private val nPoint = curve.decodePoint(hexToBytes(N_COMPRESSED_HEX)).normalize()
    private val random = SecureRandom()

    enum class ErrorCode {
        INVALID_INPUT,
        INVALID_LENGTH,
        INVALID_POINT,
        IDENTITY_POINT,
        NON_SUBGROUP_POINT,
        INVALID_SCALAR,
        CONFIRMATION_MISMATCH,
        INVALID_STATE,
    }

    class Spake2PlusException(
        val code: ErrorCode,
        message: String,
    ) : IllegalArgumentException(message)

    data class Keys(
        val kMain: ByteArray,
        val kConfirmP: ByteArray,
        val kConfirmV: ByteArray,
        val kShared: ByteArray,
    ) {
        override fun equals(other: Any?): Boolean =
            other is Keys &&
                kMain.contentEquals(other.kMain) &&
                kConfirmP.contentEquals(other.kConfirmP) &&
                kConfirmV.contentEquals(other.kConfirmV) &&
                kShared.contentEquals(other.kShared)

        override fun hashCode(): Int = listOf(
            kMain.contentHashCode(),
            kConfirmP.contentHashCode(),
            kConfirmV.contentHashCode(),
            kShared.contentHashCode(),
        ).hashCode()
    }

    data class ProverInit(val x: ByteArray, val shareP: ByteArray) {
        override fun equals(other: Any?): Boolean =
            other is ProverInit && x.contentEquals(other.x) && shareP.contentEquals(other.shareP)

        override fun hashCode(): Int = 31 * x.contentHashCode() + shareP.contentHashCode()
    }

    data class Finish(
        val shareP: ByteArray,
        val shareV: ByteArray,
        val z: ByteArray,
        val v: ByteArray,
        val transcript: ByteArray,
        val keys: Keys,
        val confirmation: ByteArray,
        val expectedConfirmation: ByteArray,
    ) {
        override fun equals(other: Any?): Boolean =
            other is Finish &&
                shareP.contentEquals(other.shareP) &&
                shareV.contentEquals(other.shareV) &&
                z.contentEquals(other.z) &&
                v.contentEquals(other.v) &&
                transcript.contentEquals(other.transcript) &&
                keys == other.keys &&
                confirmation.contentEquals(other.confirmation) &&
                expectedConfirmation.contentEquals(other.expectedConfirmation)

        override fun hashCode(): Int = listOf(
            shareP.contentHashCode(),
            shareV.contentHashCode(),
            z.contentHashCode(),
            v.contentHashCode(),
            transcript.contentHashCode(),
            keys.hashCode(),
            confirmation.contentHashCode(),
            expectedConfirmation.contentHashCode(),
        ).hashCode()
    }

    data class VerifierFinish(val y: ByteArray, val finish: Finish) {
        override fun equals(other: Any?): Boolean =
            other is VerifierFinish && y.contentEquals(other.y) && finish == other.finish

        override fun hashCode(): Int = 31 * y.contentHashCode() + finish.hashCode()
    }

    fun proverInit(w0: ByteArray, x: ByteArray? = null): ProverInit {
        registrationScalar(w0, "w0", allowZero = true)
        val xBytes = ephemeralScalar(x, "x")
        val xValue = BigInteger(1, xBytes)
        val shareP = base.multiply(xValue)
            .add(mPoint.multiply(BigInteger(1, w0)))
            .normalize()
        return ProverInit(xBytes, encodePoint(shareP, "shareP"))
    }

    fun proverFinish(
        w0: ByteArray,
        w1: ByteArray,
        x: ByteArray,
        shareV: ByteArray,
        context: ByteArray,
        idProver: ByteArray,
        idVerifier: ByteArray,
    ): Finish {
        registrationScalar(w0, "w0", allowZero = true)
        registrationScalar(w1, "w1", allowZero = false)
        registrationScalar(x, "x", allowZero = false)
        val shareVPoint = decodePoint(shareV, "shareV")
        val sharePPoint = base.multiply(BigInteger(1, x))
            .add(mPoint.multiply(BigInteger(1, w0)))
            .normalize()
        val unblindedShareV = shareVPoint.subtract(
            nPoint.multiply(BigInteger(1, w0))
        ).normalize()
        if (unblindedShareV.isInfinity) {
            fail(ErrorCode.IDENTITY_POINT, "shareV unblinds to the identity point")
        }
        val zPoint = unblindedShareV.multiply(BigInteger(1, x)).normalize()
        val vPoint = unblindedShareV.multiply(BigInteger(1, w1)).normalize()
        return finish(
            shareP = sharePPoint,
            shareV = shareVPoint,
            z = zPoint,
            v = vPoint,
            w0 = w0,
            context = context,
            idProver = idProver,
            idVerifier = idVerifier,
            proverRole = true,
        )
    }

    fun verifierFinish(
        w0: ByteArray,
        L: ByteArray,
        shareP: ByteArray,
        context: ByteArray,
        idProver: ByteArray,
        idVerifier: ByteArray,
        y: ByteArray? = null,
    ): VerifierFinish {
        registrationScalar(w0, "w0", allowZero = true)
        val yBytes = ephemeralScalar(y, "y")
        val yValue = BigInteger(1, yBytes)
        val LPoint = decodePoint(L, "L")
        val sharePPoint = decodePoint(shareP, "shareP")
        val shareVPoint = base.multiply(yValue)
            .add(nPoint.multiply(BigInteger(1, w0)))
            .normalize()
        val unblindedShareP = sharePPoint.subtract(
            mPoint.multiply(BigInteger(1, w0))
        ).normalize()
        if (unblindedShareP.isInfinity) {
            fail(ErrorCode.IDENTITY_POINT, "shareP unblinds to the identity point")
        }
        val zPoint = unblindedShareP.multiply(yValue).normalize()
        val vPoint = LPoint.multiply(yValue).normalize()
        val finish = finish(
            shareP = sharePPoint,
            shareV = shareVPoint,
            z = zPoint,
            v = vPoint,
            w0 = w0,
            context = context,
            idProver = idProver,
            idVerifier = idVerifier,
            proverRole = false,
        )
        return VerifierFinish(yBytes, finish)
    }

    fun transcript(
        context: ByteArray,
        idProver: ByteArray,
        idVerifier: ByteArray,
        shareP: ByteArray,
        shareV: ByteArray,
        z: ByteArray,
        v: ByteArray,
        w0: ByteArray,
    ): ByteArray {
        if (w0.size != SCALAR_BYTES) {
            fail(ErrorCode.INVALID_LENGTH, "w0 must be ${SCALAR_BYTES} bytes")
        }
        val out = java.io.ByteArrayOutputStream()
        out.write(lengthPrefixed(context))
        out.write(lengthPrefixed(idProver))
        out.write(lengthPrefixed(idVerifier))
        out.write(lengthPrefixed(encodePoint(mPoint, "M")))
        out.write(lengthPrefixed(encodePoint(nPoint, "N")))
        out.write(lengthPrefixed(encodePoint(decodePoint(shareP, "shareP"), "shareP")))
        out.write(lengthPrefixed(encodePoint(decodePoint(shareV, "shareV"), "shareV")))
        out.write(lengthPrefixed(encodePoint(decodePoint(z, "Z"), "Z")))
        out.write(lengthPrefixed(encodePoint(decodePoint(v, "V"), "V")))
        out.write(lengthPrefixed(w0))
        return out.toByteArray()
    }

    fun deriveKeys(transcript: ByteArray): Keys {
        val kMain = sha256(transcript)
        val confirmation = hkdf(
            salt = ByteArray(0),
            ikm = kMain,
            info = "ConfirmationKeys".toByteArray(Charsets.UTF_8),
            length = CONFIRMATION_BYTES * 2,
        )
        return Keys(
            kMain = kMain,
            kConfirmP = confirmation.copyOfRange(0, CONFIRMATION_BYTES),
            kConfirmV = confirmation.copyOfRange(CONFIRMATION_BYTES, CONFIRMATION_BYTES * 2),
            kShared = hkdf(
                salt = ByteArray(0),
                ikm = kMain,
                info = "SharedKey".toByteArray(Charsets.UTF_8),
                length = 32,
            ),
        )
    }

    fun confirmations(keys: Keys, shareP: ByteArray, shareV: ByteArray): Pair<ByteArray, ByteArray> {
        val encodedP = encodePoint(decodePoint(shareP, "shareP"), "shareP")
        val encodedV = encodePoint(decodePoint(shareV, "shareV"), "shareV")
        return hmac(keys.kConfirmP, encodedV) to hmac(keys.kConfirmV, encodedP)
    }

    fun assertConfirmation(expected: ByteArray, received: ByteArray) {
        if (expected.size != CONFIRMATION_BYTES || received.size != CONFIRMATION_BYTES) {
            fail(ErrorCode.INVALID_LENGTH, "confirmation must be ${CONFIRMATION_BYTES} bytes")
        }
        if (!MessageDigest.isEqual(expected, received)) {
            fail(ErrorCode.CONFIRMATION_MISMATCH, "confirmation mismatch")
        }
    }

    fun scalarBytes(value: BigInteger): ByteArray {
        val reduced = value.mod(order)
        val raw = reduced.toByteArray()
        val out = ByteArray(SCALAR_BYTES)
        val copy = if (raw.size > SCALAR_BYTES) {
            raw.copyOfRange(raw.size - SCALAR_BYTES, raw.size)
        } else {
            raw
        }
        copy.copyInto(out, SCALAR_BYTES - copy.size)
        return out
    }

    private fun finish(
        shareP: ECPoint,
        shareV: ECPoint,
        z: ECPoint,
        v: ECPoint,
        w0: ByteArray,
        context: ByteArray,
        idProver: ByteArray,
        idVerifier: ByteArray,
        proverRole: Boolean,
    ): Finish {
        val sharePBytes = encodePoint(shareP, "shareP")
        val shareVBytes = encodePoint(shareV, "shareV")
        val zBytes = encodePoint(z, "Z")
        val vBytes = encodePoint(v, "V")
        val transcript = transcript(
            context = context,
            idProver = idProver,
            idVerifier = idVerifier,
            shareP = sharePBytes,
            shareV = shareVBytes,
            z = zBytes,
            v = vBytes,
            w0 = w0,
        )
        val keys = deriveKeys(transcript)
        val confirmation = confirmations(keys, sharePBytes, shareVBytes)
        return Finish(
            shareP = sharePBytes,
            shareV = shareVBytes,
            z = zBytes,
            v = vBytes,
            transcript = transcript,
            keys = keys,
            confirmation = if (proverRole) confirmation.first else confirmation.second,
            expectedConfirmation = if (proverRole) confirmation.second else confirmation.first,
        )
    }

    private fun registrationScalar(value: ByteArray, name: String, allowZero: Boolean): BigInteger {
        if (value.size != SCALAR_BYTES) {
            fail(ErrorCode.INVALID_LENGTH, "$name must be ${SCALAR_BYTES} bytes")
        }
        val scalar = BigInteger(1, value)
        if (scalar >= order || (!allowZero && scalar.signum() == 0)) {
            val range = if (allowZero) "[0, n-1]" else "[1, n-1]"
            fail(ErrorCode.INVALID_SCALAR, "$name must be in the range $range")
        }
        return scalar
    }

    private fun ephemeralScalar(value: ByteArray?, name: String): ByteArray {
        if (value != null) {
            registrationScalar(value, name, allowZero = false)
            return value.copyOf()
        }
        repeat(64) {
            val candidate = ByteArray(SCALAR_BYTES).also(random::nextBytes)
            val scalar = BigInteger(1, candidate)
            if (scalar.signum() > 0 && scalar < order) return candidate
        }
        fail(ErrorCode.INVALID_SCALAR, "could not generate an ephemeral scalar")
    }

    private fun decodePoint(value: ByteArray, name: String): ECPoint {
        if (value.size == 1 && value[0] == 0.toByte()) {
            fail(ErrorCode.IDENTITY_POINT, "$name is the identity point")
        }
        if (value.size != 65 || value[0] != 0x04.toByte()) {
            fail(ErrorCode.INVALID_LENGTH, "$name must be an uncompressed SEC1 P-256 point")
        }
        val point = try {
            curve.decodePoint(value).normalize()
        } catch (error: Exception) {
            fail(ErrorCode.INVALID_POINT, "$name is not a valid P-256 point")
        }
        if (point.isInfinity) fail(ErrorCode.IDENTITY_POINT, "$name is the identity point")
        if (!point.isValid) fail(ErrorCode.INVALID_POINT, "$name is not a valid P-256 point")
        return point
    }

    private fun encodePoint(point: ECPoint, name: String): ByteArray {
        if (point.isInfinity) fail(ErrorCode.IDENTITY_POINT, "$name is the identity point")
        return point.normalize().getEncoded(false)
    }

    private fun lengthPrefixed(value: ByteArray): ByteArray {
        val out = ByteArray(8 + value.size)
        ByteBuffer.wrap(out).order(ByteOrder.LITTLE_ENDIAN).putLong(value.size.toLong()).put(value)
        return out
    }

    private fun hkdf(salt: ByteArray, ikm: ByteArray, info: ByteArray, length: Int): ByteArray {
        val effectiveSalt = if (salt.isEmpty()) ByteArray(32) else salt
        val prk = hmac(effectiveSalt, ikm)
        val out = ByteArray(length)
        var previous = ByteArray(0)
        var offset = 0
        var counter = 1
        while (offset < length) {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(prk, "HmacSHA256"))
            mac.update(previous)
            mac.update(info)
            mac.update(counter.toByte())
            previous = mac.doFinal()
            val copy = minOf(previous.size, length - offset)
            previous.copyInto(out, offset, 0, copy)
            offset += copy
            counter += 1
        }
        return out
    }

    private fun hmac(key: ByteArray, message: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(message)
    }

    private fun sha256(value: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(value)

    private fun hexToBytes(hex: String): ByteArray {
        require(hex.length % 2 == 0) { "point hex is malformed" }
        return ByteArray(hex.length / 2) { index ->
            hex.substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
    }

    private fun fail(code: ErrorCode, message: String): Nothing =
        throw Spake2PlusException(code, message)
}
