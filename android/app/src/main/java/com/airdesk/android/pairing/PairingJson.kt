package com.airdesk.android.pairing

import kotlinx.serialization.json.Json

object PairingJson {
    val strict: Json = Json {
        ignoreUnknownKeys = false
        isLenient = false
        coerceInputValues = false
        explicitNulls = true
        encodeDefaults = true
    }

    val pretty: Json = Json(strict) {
        prettyPrint = true
    }
}
