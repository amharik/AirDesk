package com.airdesk.android.identity

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.airdesk.android.util.Base64Url
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec

class DeviceIdentityStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val lock = Any()

    fun loadOrCreate(): DeviceIdentity {
        ensureKey()
        val keyStore = loadKeyStore()
        val certificate = keyStore.getCertificate(ALIAS) as? X509Certificate
            ?: error("AirDesk identity certificate is missing")
        val privateKey = keyStore.getKey(ALIAS, null) as? PrivateKey
            ?: error("AirDesk identity private key is missing")
        val spki = certificate.publicKey.encoded
        val createdAt = prefs.getLong(KEY_CREATED_AT, 0L).takeIf { it > 0L }
            ?: certificate.notBefore.time.also {
                prefs.edit().putLong(KEY_CREATED_AT, it).apply()
            }
        val savedName = prefs.getString(KEY_DISPLAY_NAME, null)
        val displayName = savedName?.takeIf { it.isNotBlank() } ?: defaultDisplayName().also {
            prefs.edit().putString(KEY_DISPLAY_NAME, it).apply()
        }
        val extractable = runCatching { privateKey.encoded != null }.getOrDefault(false)
        return DeviceIdentity(
            alias = ALIAS,
            deviceId = DeviceId.fromSpki(spki),
            displayName = displayName,
            publicKeyBase64Url = Base64Url.encode(spki),
            publicKeySpki = spki,
            createdAtEpochMillis = createdAt,
            keyAlgorithm = privateKey.algorithm ?: certificate.publicKey.algorithm,
            privateKeyExtractable = extractable,
        )
    }

    fun setDisplayName(name: String): String {
        val trimmed = name.trim()
        require(trimmed.isNotEmpty()) { "display name cannot be empty" }
        prefs.edit().putString(KEY_DISPLAY_NAME, trimmed).apply()
        return trimmed
    }

    private fun ensureKey() {
        if (loadKeyStore().containsAlias(ALIAS)) return
        synchronized(lock) {
            if (loadKeyStore().containsAlias(ALIAS)) return
            val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE)
            val spec = KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
            )
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setUserAuthenticationRequired(false)
                .build()
            generator.initialize(spec)
            generator.generateKeyPair()
        }
    }

    private fun loadKeyStore(): KeyStore =
        KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun defaultDisplayName(): String {
        val model = Build.MODEL?.trim().orEmpty()
        return if (model.isEmpty()) "AirDesk Android" else "AirDesk on $model"
    }

    companion object {
        const val ALIAS = "airdesk.device.p256"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val PREFS = "airdesk_identity"
        private const val KEY_DISPLAY_NAME = "display_name"
        private const val KEY_CREATED_AT = "identity_created_at"
    }
}
