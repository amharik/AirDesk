package com.airdesk.android.display

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidMediaCodecStreamTest {
    private fun descriptor(
        name: String,
        mimeType: String,
        hardwareAccelerated: Boolean,
        supportsSurfaceInput: Boolean = true,
    ): AndroidCodecDescriptor = AndroidCodecDescriptor(
        name = name,
        mimeType = mimeType,
        hardwareAccelerated = hardwareAccelerated,
        supportsSurfaceInput = supportsSurfaceInput,
    )

    @Test
    fun capabilitiesRequireSurfaceInputAndExcludeUnknownCodecs() {
        val capabilities = AndroidVideoCapabilities.fromDescriptors(
            listOf(
                descriptor("c2.qti.hevc.encoder", "video/hevc", hardwareAccelerated = true),
                descriptor("OMX.google.h264.encoder", "video/avc", hardwareAccelerated = false),
                descriptor(
                    "c2.qti.av1.encoder",
                    "video/av01",
                    hardwareAccelerated = true,
                    supportsSurfaceInput = false,
                ),
                descriptor("c2.qti.vp9.encoder", "video/x-vnd.on2.vp9", hardwareAccelerated = true),
            ),
        )

        assertEquals("c2.qti.hevc.encoder", capabilities.hardwareCodecs[AndroidVideoCodec.HEVC])
        assertEquals("OMX.google.h264.encoder", capabilities.softwareCodecs[AndroidVideoCodec.H264])
        assertFalse(capabilities.supports(AndroidVideoCodec.AV1))
        assertTrue(capabilities.isHardwareSupported(AndroidVideoCodec.HEVC))
        assertFalse(capabilities.isHardwareSupported(AndroidVideoCodec.H264))
    }

    @Test
    fun preferredHardwareCodecIsSelectedWithoutFallback() {
        val capabilities = AndroidVideoCapabilities(
            hardwareCodecs = mapOf(
                AndroidVideoCodec.HEVC to "c2.qti.hevc.encoder",
                AndroidVideoCodec.H264 to "c2.qti.h264.encoder",
            ),
        )

        val selection = AndroidCodecSelector.select(
            capabilities = capabilities,
            preferred = AndroidVideoCodec.HEVC,
            allowSoftwareFallback = true,
        )

        assertEquals(AndroidVideoCodec.HEVC, selection?.codec)
        assertEquals("c2.qti.hevc.encoder", selection?.codecName)
        assertTrue(selection?.hardwareAccelerated == true)
        assertFalse(selection?.fallback == true)
        assertFalse(selection?.softwareFallback == true)
    }

    @Test
    fun hevcFallsBackToHardwareH264WhenPreferredEncoderIsMissing() {
        val capabilities = AndroidVideoCapabilities(
            hardwareCodecs = mapOf(AndroidVideoCodec.H264 to "c2.qti.h264.encoder"),
        )

        val selection = AndroidCodecSelector.select(
            capabilities = capabilities,
            preferred = AndroidVideoCodec.HEVC,
            allowSoftwareFallback = true,
        )

        assertEquals(AndroidVideoCodec.H264, selection?.codec)
        assertTrue(selection?.hardwareAccelerated == true)
        assertTrue(selection?.fallback == true)
        assertFalse(selection?.softwareFallback == true)
    }

    @Test
    fun h264PreferenceDoesNotSilentlySwitchToHevc() {
        val capabilities = AndroidVideoCapabilities(
            hardwareCodecs = mapOf(AndroidVideoCodec.HEVC to "c2.qti.hevc.encoder"),
        )

        assertNull(
            AndroidCodecSelector.select(
                capabilities = capabilities,
                preferred = AndroidVideoCodec.H264,
                allowSoftwareFallback = false,
            ),
        )
    }

    @Test
    fun softwareFallbackIsTruthfulAndCanBeDisabled() {
        val capabilities = AndroidVideoCapabilities(
            softwareCodecs = mapOf(AndroidVideoCodec.H264 to "OMX.google.h264.encoder"),
        )

        val fallback = AndroidCodecSelector.select(
            capabilities = capabilities,
            preferred = AndroidVideoCodec.HEVC,
            allowSoftwareFallback = true,
        )
        assertEquals(AndroidVideoCodec.H264, fallback?.codec)
        assertFalse(fallback?.hardwareAccelerated == true)
        assertTrue(fallback?.fallback == true)
        assertTrue(fallback?.softwareFallback == true)

        assertNull(
            AndroidCodecSelector.select(
                capabilities = capabilities,
                preferred = AndroidVideoCodec.HEVC,
                allowSoftwareFallback = false,
            ),
        )
    }

    @Test
    fun av1AndUnsupportedRequestsFailWithoutInventingAnEncoder() {
        val capabilities = AndroidVideoCapabilities(
            hardwareCodecs = mapOf(AndroidVideoCodec.AV1 to "c2.qti.av1.encoder"),
        )

        assertNull(
            AndroidCodecSelector.select(
                capabilities = capabilities,
                preferred = AndroidVideoCodec.AV1,
                allowSoftwareFallback = true,
            ),
        )
        assertNull(
            AndroidCodecSelector.select(
                capabilities = AndroidVideoCapabilities.none,
                preferred = AndroidVideoCodec.HEVC,
                allowSoftwareFallback = true,
            ),
        )
    }

    @Test
    fun codecMimeTypesRoundTrip() {
        AndroidVideoCodec.entries.forEach { codec ->
            assertEquals(codec, AndroidVideoCodec.fromMimeType(codec.mimeType))
        }
        assertNull(AndroidVideoCodec.fromMimeType("video/x-vnd.on2.vp9"))
    }

    @Test
    fun configurationRejectsOutOfRangeValues() {
        val valid = AndroidDisplayCaptureConfiguration()
        assertEquals(valid, valid.validate())

        listOf(
            valid.copy(framesPerSecond = 0),
            valid.copy(keyframeIntervalSeconds = 31),
            valid.copy(averageBitRate = 99_999),
            valid.copy(maximumDimension = 8193),
        ).forEach { configuration ->
            assertThrows(AndroidDisplayException::class.java) {
                configuration.validate()
            }
        }
    }

    @Test
    fun captureSizeRejectsInvalidDimensionsAndDensity() {
        AndroidDisplayCaptureSize(1920, 1080, 420).validate(maximumDimension = 4096)

        assertThrows(AndroidDisplayException::class.java) {
            AndroidDisplayCaptureSize(15, 1080, 420).validate(maximumDimension = 4096)
        }
        assertThrows(AndroidDisplayException::class.java) {
            AndroidDisplayCaptureSize(1920, 1080, 0).validate(maximumDimension = 4096)
        }
        assertThrows(AndroidDisplayException::class.java) {
            AndroidDisplayCaptureSize(1920, 5000, 420).validate(maximumDimension = 4096)
        }
    }

    @Test
    fun newStreamStartsWithTruthfulIdleSnapshot() {
        val snapshot = AndroidMediaCodecStream(AndroidVideoCapabilities.none).snapshot()

        assertEquals(AndroidDisplayCaptureState.IDLE, snapshot.state)
        assertNull(snapshot.codec)
        assertNull(snapshot.codecName)
        assertNull(snapshot.width)
        assertNull(snapshot.height)
        assertNull(snapshot.lastError)
        assertEquals(AndroidDisplayStreamMetrics(), snapshot.metrics)
    }
}
