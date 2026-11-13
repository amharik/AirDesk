package com.airdesk.android.core

import com.airdesk.android.pairing.KeyValueStore

enum class CoreFeature(val storageKey: String, val label: String) {
    MOVEMENT("airdesk.core.movement", "Pointer movement"),
    ENVELOPE("airdesk.core.envelope", "ADFP envelope"),
    PAIRING("airdesk.core.pairing", "Pairing"),
    SYNC("airdesk.core.sync", "Workspace sync"),
}

enum class CoreFeaturePath(val storageValue: String, val label: String) {
    NATIVE("native", "Native"),
    CORE("core", "Shared core"),
}

enum class CoreFallbackReason(val storageValue: String, val label: String) {
    NONE("none", "Ready"),
    BINDING_UNAVAILABLE("binding-unavailable", "Binding not exported"),
    INDEPENDENT_REVIEW_REQUIRED("independent-review-required", "Independent review required"),
    FIXTURE_MIGRATION_PENDING("fixture-migration-pending", "Fixture migration pending"),
}

data class CoreFeatureSelection(
    val feature: CoreFeature,
    val requested: CoreFeaturePath,
    val active: CoreFeaturePath,
    val reason: CoreFallbackReason,
) {
    val isFallback: Boolean get() = requested != active
    val telemetry: String
        get() = "${feature.storageKey.substringAfterLast('.')}=${active.storageValue} " +
            "requested=${requested.storageValue} reason=${reason.storageValue}"
}

data class CoreCutoverAvailability(
    val movement: Boolean = false,
    val envelope: Boolean = false,
    val pairing: Boolean = false,
    val sync: Boolean = false,
)

object CoreCutoverPolicy {
    fun resolve(
        feature: CoreFeature,
        requested: CoreFeaturePath,
        availability: CoreCutoverAvailability = CoreCutoverAvailability(),
    ): CoreFeatureSelection {
        if (requested == CoreFeaturePath.NATIVE) {
            return CoreFeatureSelection(feature, requested, CoreFeaturePath.NATIVE, CoreFallbackReason.NONE)
        }
        val reason = when (feature) {
            CoreFeature.MOVEMENT ->
                if (availability.movement) null else CoreFallbackReason.BINDING_UNAVAILABLE
            CoreFeature.ENVELOPE -> CoreFallbackReason.BINDING_UNAVAILABLE
            CoreFeature.PAIRING -> CoreFallbackReason.INDEPENDENT_REVIEW_REQUIRED
            CoreFeature.SYNC -> CoreFallbackReason.FIXTURE_MIGRATION_PENDING
        }
        return CoreFeatureSelection(
            feature = feature,
            requested = requested,
            active = if (reason == null) CoreFeaturePath.CORE else CoreFeaturePath.NATIVE,
            reason = reason ?: CoreFallbackReason.NONE,
        )
    }
}

class CoreCutoverStore(
    private val store: KeyValueStore,
    private val availability: CoreCutoverAvailability = CoreCutoverAvailability(),
) {
    private val requested = CoreFeature.entries.associateWith { feature ->
        store.getString(feature.storageKey)
            ?.let { value -> CoreFeaturePath.entries.firstOrNull { it.storageValue == value } }
            ?: CoreFeaturePath.NATIVE
    }.toMutableMap()

    fun get(feature: CoreFeature): CoreFeatureSelection =
        CoreCutoverPolicy.resolve(feature, requested.getValue(feature), availability)

    fun set(feature: CoreFeature, path: CoreFeaturePath): CoreFeatureSelection {
        requested[feature] = path
        store.putString(feature.storageKey, path.storageValue)
        return get(feature)
    }

    fun snapshot(): List<CoreFeatureSelection> = CoreFeature.entries.map(::get)

    fun telemetry(): String = snapshot().joinToString(";") { it.telemetry }
}
