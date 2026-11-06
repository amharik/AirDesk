package com.airdesk.android.pairing

import android.content.SharedPreferences

interface KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String)
}

class SharedPreferencesKeyValueStore(
    private val prefs: SharedPreferences,
) : KeyValueStore {
    override fun getString(key: String): String? = prefs.getString(key, null)

    override fun putString(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }
}
