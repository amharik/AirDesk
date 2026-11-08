package com.airdesk.android.pairing

import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets
import java.text.Normalizer
import org.bouncycastle.asn1.x9.ECNamedCurveTable
import org.bouncycastle.crypto.generators.SCrypt

data class Spake2PlusPasswordRegistration(
    val w0: ByteArray,
    val w1: ByteArray,
    val salt: ByteArray,
    val L: ByteArray,
    val profileName: String = Spake2PlusRegistration.PROFILE_NAME,
    val scryptN: Int = Spake2PlusRegistration.SCRYPT_N,
    val scryptR: Int = Spake2PlusRegistration.SCRYPT_R,
    val scryptP: Int = Spake2PlusRegistration.SCRYPT_P,
    val dkLen: Int = Spake2PlusRegistration.DK_LEN,
) {
    override fun equals(other: Any?): Boolean =
        other is Spake2PlusPasswordRegistration &&
            w0.contentEquals(other.w0) &&
            w1.contentEquals(other.w1) &&
            salt.contentEquals(other.salt) &&
            L.contentEquals(other.L) &&
            profileName == other.profileName &&
            scryptN == other.scryptN &&
            scryptR == other.scryptR &&
            scryptP == other.scryptP &&
            dkLen == other.dkLen

    override fun hashCode(): Int = listOf(
        w0.contentHashCode(),
        w1.contentHashCode(),
        salt.contentHashCode(),
        L.contentHashCode(),
        profileName,
        scryptN,
        scryptR,
        scryptP,
        dkLen,
    ).hashCode()
}

object Spake2PlusRegistration {
    const val PROFILE_NAME = "scrypt"
    const val SCRYPT_N = 32768
    const val SCRYPT_R = 8
    const val SCRYPT_P = 1
    const val DK_LEN = 80

    const val SCALAR_BYTES = 32
    const val MIN_SALT_BYTES = 16
    const val MAX_SALT_BYTES = 64

    private const val HALF_LEN = DK_LEN / 2
    private val curve = ECNamedCurveTable.getByName("secp256r1")
    private val order = curve.n
    private val base = curve.g

    data class Scalars(val w0: ByteArray, val w1: ByteArray) {
        override fun equals(other: Any?): Boolean =
            other is Scalars && w0.contentEquals(other.w0) && w1.contentEquals(other.w1)

        override fun hashCode(): Int = 31 * w0.contentHashCode() + w1.contentHashCode()
    }

    fun create(
        password: String,
        salt: ByteArray,
        idProver: ByteArray = ByteArray(0),
        idVerifier: ByteArray = ByteArray(0),
    ): Spake2PlusPasswordRegistration {
        require(password.isNotEmpty()) { "password must not be empty" }
        val normalized = Normalizer.normalize(password, Normalizer.Form.NFKC)
        require(normalized.isNotEmpty()) { "password must not be empty" }
        return createBytes(normalized.toByteArray(StandardCharsets.UTF_8), salt, idProver, idVerifier)
    }

    fun createBytes(
        password: ByteArray,
        salt: ByteArray,
        idProver: ByteArray = ByteArray(0),
        idVerifier: ByteArray = ByteArray(0),
    ): Spake2PlusPasswordRegistration {
        require(password.isNotEmpty()) { "password must not be empty" }
        require(salt.size in MIN_SALT_BYTES..MAX_SALT_BYTES) {
            "salt must be $MIN_SALT_BYTES to $MAX_SALT_BYTES bytes"
        }
        val scalars = deriveScalars(password, salt, idProver, idVerifier)
        return Spake2PlusPasswordRegistration(
            w0 = scalars.w0,
            w1 = scalars.w1,
            salt = salt.copyOf(),
            L = registrationRecord(scalars.w1),
        )
    }

    fun deriveScalars(
        password: ByteArray,
        salt: ByteArray,
        idProver: ByteArray = ByteArray(0),
        idVerifier: ByteArray = ByteArray(0),
    ): Scalars {
        require(password.isNotEmpty()) { "password must not be empty" }
        require(salt.size in MIN_SALT_BYTES..MAX_SALT_BYTES) {
            "salt must be $MIN_SALT_BYTES to $MAX_SALT_BYTES bytes"
        }
        val material = canonicalMaterial(password, idProver, idVerifier)
        val output = SCrypt.generate(material, salt, SCRYPT_N, SCRYPT_R, SCRYPT_P, DK_LEN)
        val w0 = wideScalar(output.copyOfRange(0, HALF_LEN))
        val w1 = wideScalar(output.copyOfRange(HALF_LEN, DK_LEN))
        require(BigInteger(1, w1).signum() != 0) { "derived w1 must not be zero" }
        return Scalars(w0, w1)
    }

    fun canonicalMaterial(
        password: ByteArray,
        idProver: ByteArray = ByteArray(0),
        idVerifier: ByteArray = ByteArray(0),
    ): ByteArray {
        val out = ByteArray(8 + password.size + 8 + idProver.size + 8 + idVerifier.size)
        val buffer = ByteBuffer.wrap(out).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putLong(password.size.toLong()).put(password)
        buffer.putLong(idProver.size.toLong()).put(idProver)
        buffer.putLong(idVerifier.size.toLong()).put(idVerifier)
        return out
    }

    fun registrationRecord(w1: ByteArray): ByteArray {
        val scalar = BigInteger(1, w1)
        require(scalar.signum() != 0 && scalar < order) { "w1 must be in [1, n-1]" }
        return base.multiply(scalar).normalize().getEncoded(false)
    }

    fun scalarBytes(value: BigInteger): ByteArray {
        val reduced = value.mod(order)
        val raw = reduced.toByteArray()
        val out = ByteArray(SCALAR_BYTES)
        val copy = if (raw.size > SCALAR_BYTES) raw.copyOfRange(raw.size - SCALAR_BYTES, raw.size) else raw
        copy.copyInto(out, SCALAR_BYTES - copy.size)
        return out
    }

    private fun wideScalar(bytes: ByteArray): ByteArray = scalarBytes(BigInteger(1, bytes))
}
