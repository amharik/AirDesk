package com.airdesk.android.util

import java.util.Base64

object Base64Url {
    private val allowed = Regex("^[A-Za-z0-9_-]+$")

    fun encode(bytes: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)

    fun decode(value: String): ByteArray {
        require(value.isNotEmpty()) { "base64url value is empty" }
        require(value.length % 4 != 1) { "invalid base64url length" }
        require(allowed.matches(value)) { "invalid base64url characters" }
        return Base64.getUrlDecoder().decode(value)
    }
}
