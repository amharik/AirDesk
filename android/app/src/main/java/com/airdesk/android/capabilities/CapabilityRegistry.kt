package com.airdesk.android.capabilities

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

class CapabilityRegistryError(
    val code: Code,
    message: String,
) : IllegalArgumentException(message) {
    enum class Code {
        INVALID_CAP_URI,
        INVALID_PROVIDER_DEVICE_ID,
        INVALID_VERSION,
        INVALID_PERMISSIONS,
        INVALID_EXECUTION,
        INVALID_TRANSPORT,
        INVALID_CONSTRAINTS,
        INVALID_LABEL,
        INVALID_SUMMARY,
        INVALID_NOTE,
    }
}

class CapabilityRegistry {
    private data class Key(
        val providerDeviceId: String,
        val capUri: String,
        val version: Int,
    )

    private val entries = LinkedHashMap<Key, CapabilityDescriptor>()

    val size: Int
        get() = entries.size

    fun register(descriptor: CapabilityDescriptor): Boolean {
        val validated = validate(descriptor)
        val key = Key(validated.providerDeviceId, validated.capUri, validated.version)
        val added = entries[key] == null
        entries[key] = validated
        return added
    }

    fun remove(providerDeviceId: String, capUri: String, version: Int? = null): Int {
        val keys = entries.keys.filter {
            it.providerDeviceId == providerDeviceId &&
                it.capUri == capUri &&
                (version == null || it.version == version)
        }
        keys.forEach { entries.remove(it) }
        return keys.size
    }

    fun updateAvailability(
        providerDeviceId: String,
        capUri: String,
        version: Int,
        availability: Availability,
    ): Boolean = update(
        providerDeviceId = providerDeviceId,
        capUri = capUri,
        version = version,
        availability = availability,
        authorization = null,
    )

    fun updateAuthorization(
        providerDeviceId: String,
        capUri: String,
        version: Int,
        authorization: Authorization,
    ): Boolean = update(
        providerDeviceId = providerDeviceId,
        capUri = capUri,
        version = version,
        availability = null,
        authorization = authorization,
    )

    fun descriptor(
        providerDeviceId: String,
        capUri: String,
        version: Int,
    ): CapabilityDescriptor? = entries[Key(providerDeviceId, capUri, version)]

    fun descriptors(): List<CapabilityDescriptor> =
        entries.values.sortedWith(
            compareBy<CapabilityDescriptor> { it.capUri }
                .thenBy { it.providerDeviceId }
                .thenByDescending { it.version }
                .thenBy { it.transport }
                .thenBy { it.execution },
        )

    fun clear() {
        entries.clear()
    }

    private fun update(
        providerDeviceId: String,
        capUri: String,
        version: Int,
        availability: Availability?,
        authorization: Authorization?,
    ): Boolean {
        val key = Key(providerDeviceId, capUri, version)
        val existing = entries[key] ?: return false
        entries[key] = validate(
            existing.copy(
                availability = availability ?: existing.availability,
                authorization = authorization ?: existing.authorization,
            ),
        )
        return true
    }

    private fun validate(descriptor: CapabilityDescriptor): CapabilityDescriptor {
        if (!bounded(descriptor.providerDeviceId, 512)) {
            fail(CapabilityRegistryError.Code.INVALID_PROVIDER_DEVICE_ID)
        }
        if (!bounded(descriptor.capUri, 512) || !CAP_URI.matches(descriptor.capUri)) {
            fail(CapabilityRegistryError.Code.INVALID_CAP_URI)
        }
        if (descriptor.version < 1) {
            fail(CapabilityRegistryError.Code.INVALID_VERSION)
        }
        if (descriptor.permissions.size > 32 ||
            descriptor.permissions.any { !bounded(it, 128) } ||
            descriptor.permissions.toSet().size != descriptor.permissions.size
        ) {
            fail(CapabilityRegistryError.Code.INVALID_PERMISSIONS)
        }
        if (!bounded(descriptor.execution, 64)) {
            fail(CapabilityRegistryError.Code.INVALID_EXECUTION)
        }
        if (!bounded(descriptor.transport, 64)) {
            fail(CapabilityRegistryError.Code.INVALID_TRANSPORT)
        }
        if (!validConstraints(descriptor.constraints)) {
            fail(CapabilityRegistryError.Code.INVALID_CONSTRAINTS)
        }
        if (!bounded(descriptor.label, 128)) {
            fail(CapabilityRegistryError.Code.INVALID_LABEL)
        }
        if (!bounded(descriptor.summary, 512)) {
            fail(CapabilityRegistryError.Code.INVALID_SUMMARY)
        }
        if (!bounded(descriptor.note, 2048)) {
            fail(CapabilityRegistryError.Code.INVALID_NOTE)
        }
        return descriptor
    }

    private fun bounded(value: String, maximum: Int): Boolean =
        value.isNotBlank() && value.length <= maximum

    private fun validConstraints(value: String): Boolean {
        if (value.length > 4096) return false
        val element = try {
            Json.parseToJsonElement(value)
        } catch (_: IllegalArgumentException) {
            return false
        }
        if (element !is JsonObject || element.size > 32) return false
        return element.all { (key, entry) ->
            CONSTRAINT_KEY.matches(key) &&
                key.length <= 64 &&
                entry is JsonPrimitive &&
                entry !is JsonNull &&
                (!entry.isString || entry.content.length <= 256)
        }
    }

    private fun fail(code: CapabilityRegistryError.Code): Nothing =
        throw CapabilityRegistryError(code, code.name.lowercase().replace('_', ' '))

    private companion object {
        val CAP_URI = Regex("^airdesk://[A-Za-z0-9._~-]+(/[A-Za-z0-9._~-]+)*$")
        val CONSTRAINT_KEY = Regex("^[A-Za-z0-9._~-]+$")
    }
}
