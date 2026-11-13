package com.airdesk.android.core

import com.airdesk.android.pairing.KeyValueStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CoreCutoverTest {
    private class MemoryStore : KeyValueStore {
        val values = mutableMapOf<String, String>()
        override fun getString(key: String): String? = values[key]
        override fun putString(key: String, value: String) {
            values[key] = value
        }
    }

    @Test
    fun defaultsToNativeWithoutFallback() {
        val store = CoreCutoverStore(MemoryStore())
        store.snapshot().forEach { selection ->
            assertEquals(CoreFeaturePath.NATIVE, selection.active)
            assertEquals(CoreFallbackReason.NONE, selection.reason)
            assertFalse(selection.isFallback)
        }
    }

    @Test
    fun respectsAvailabilityAndReviewGates() {
        val store = CoreCutoverStore(
            MemoryStore(),
            CoreCutoverAvailability(movement = true),
        )
        assertEquals(CoreFeaturePath.CORE, store.set(CoreFeature.MOVEMENT, CoreFeaturePath.CORE).active)
        assertEquals(
            CoreFallbackReason.INDEPENDENT_REVIEW_REQUIRED,
            store.set(CoreFeature.PAIRING, CoreFeaturePath.CORE).reason,
        )
        assertEquals(
            CoreFallbackReason.BINDING_UNAVAILABLE,
            store.set(CoreFeature.ENVELOPE, CoreFeaturePath.CORE).reason,
        )
        assertEquals(
            CoreFallbackReason.FIXTURE_MIGRATION_PENDING,
            store.set(CoreFeature.SYNC, CoreFeaturePath.CORE).reason,
        )
        assertTrue(store.set(CoreFeature.PAIRING, CoreFeaturePath.CORE).isFallback)
    }

    @Test
    fun persistsRequestedPathsAndIgnoresInvalidValues() {
        val memory = MemoryStore()
        val store = CoreCutoverStore(memory, CoreCutoverAvailability(movement = true))
        store.set(CoreFeature.MOVEMENT, CoreFeaturePath.CORE)
        store.set(CoreFeature.PAIRING, CoreFeaturePath.CORE)

        val reloaded = CoreCutoverStore(memory, CoreCutoverAvailability(movement = true))
        assertEquals(CoreFeaturePath.CORE, reloaded.get(CoreFeature.MOVEMENT).active)
        assertEquals(CoreFeaturePath.NATIVE, reloaded.get(CoreFeature.PAIRING).active)
        assertTrue(reloaded.telemetry().contains("pairing=native requested=core"))

        memory.putString(CoreFeature.SYNC.storageKey, "bogus")
        assertEquals(CoreFeaturePath.NATIVE, CoreCutoverStore(memory).get(CoreFeature.SYNC).requested)
    }
}
