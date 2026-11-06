package com.airdesk.android.identity

data class DeviceIdentity(
    val alias: String,
    val deviceId: String,
    val displayName: String,
    val publicKeyBase64Url: String,
    val publicKeySpki: ByteArray,
    val createdAtEpochMillis: Long,
    val keyAlgorithm: String,
    val privateKeyExtractable: Boolean,
)
