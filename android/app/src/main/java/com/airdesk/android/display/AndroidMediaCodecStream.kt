package com.airdesk.android.display

import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface

enum class AndroidVideoCodec(val mimeType: String, val wire: String) {
    HEVC("video/hevc", "hevc"),
    H264("video/avc", "h264"),
    AV1("video/av01", "av1"),
    ;

    companion object {
        fun fromMimeType(mimeType: String): AndroidVideoCodec? =
            entries.firstOrNull { it.mimeType == mimeType }
    }
}

enum class AndroidDisplayErrorCode {
    INVALID_CONFIGURATION,
    INVALID_SIZE,
    ALREADY_RUNNING,
    CODEC_UNSUPPORTED,
    ENCODER_UNAVAILABLE,
    ENCODER_CONFIGURATION_FAILED,
    ENCODER_FAILURE,
    PROJECTION_UNAVAILABLE,
    PROJECTION_STOPPED,
    VIRTUAL_DISPLAY_FAILED,
}

class AndroidDisplayException(
    val code: AndroidDisplayErrorCode,
    message: String,
    cause: Throwable? = null,
) : IllegalStateException(message, cause)

enum class AndroidDisplayCaptureState(val wire: String) {
    IDLE("idle"),
    STARTING("starting"),
    RUNNING("running"),
    STOPPED("stopped"),
    FAILED("failed"),
}

data class AndroidCodecDescriptor(
    val name: String,
    val mimeType: String,
    val hardwareAccelerated: Boolean,
    val supportsSurfaceInput: Boolean,
) {
    val codec: AndroidVideoCodec?
        get() = AndroidVideoCodec.fromMimeType(mimeType)
}

data class AndroidVideoCapabilities(
    val hardwareCodecs: Map<AndroidVideoCodec, String> = emptyMap(),
    val softwareCodecs: Map<AndroidVideoCodec, String> = emptyMap(),
) {
    fun supports(codec: AndroidVideoCodec): Boolean =
        hardwareCodecs.containsKey(codec) || softwareCodecs.containsKey(codec)

    fun isHardwareSupported(codec: AndroidVideoCodec): Boolean =
        hardwareCodecs.containsKey(codec)

    companion object {
        val none = AndroidVideoCapabilities()

        fun fromDescriptors(descriptors: List<AndroidCodecDescriptor>): AndroidVideoCapabilities {
            val hardware = LinkedHashMap<AndroidVideoCodec, String>()
            val software = LinkedHashMap<AndroidVideoCodec, String>()
            descriptors
                .sortedBy { it.name }
                .forEach { descriptor ->
                    if (!descriptor.supportsSurfaceInput) return@forEach
                    val codec = descriptor.codec ?: return@forEach
                    val target = if (descriptor.hardwareAccelerated) hardware else software
                    target.putIfAbsent(codec, descriptor.name)
                }
            return AndroidVideoCapabilities(hardware, software)
        }

        fun detect(): AndroidVideoCapabilities {
            val descriptors = mutableListOf<AndroidCodecDescriptor>()
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .filter { it.isEncoder }
                .forEach { info ->
                    info.supportedTypes.forEach { mimeType ->
                        if (AndroidVideoCodec.fromMimeType(mimeType) == null) return@forEach
                        val capabilities = runCatching {
                            info.getCapabilitiesForType(mimeType)
                        }.getOrNull() ?: return@forEach
                        val supportsSurfaceInput = capabilities.colorFormats.any {
                            it == MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
                        }
                        descriptors += AndroidCodecDescriptor(
                            name = info.name,
                            mimeType = mimeType,
                            hardwareAccelerated = isHardwareAccelerated(info),
                            supportsSurfaceInput = supportsSurfaceInput,
                        )
                    }
                }
            return fromDescriptors(descriptors)
        }

        private fun isHardwareAccelerated(info: MediaCodecInfo): Boolean =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                info.isHardwareAccelerated
            } else {
                !info.name.startsWith("OMX.google.") &&
                    !info.name.startsWith("c2.android.")
            }
    }
}

data class AndroidCodecSelection(
    val codec: AndroidVideoCodec,
    val codecName: String,
    val hardwareAccelerated: Boolean,
    val fallback: Boolean,
    val softwareFallback: Boolean,
)

object AndroidCodecSelector {
    fun select(
        capabilities: AndroidVideoCapabilities,
        preferred: AndroidVideoCodec,
        allowSoftwareFallback: Boolean,
    ): AndroidCodecSelection? {
        val candidates = when (preferred) {
            AndroidVideoCodec.HEVC -> listOf(AndroidVideoCodec.HEVC, AndroidVideoCodec.H264)
            AndroidVideoCodec.H264 -> listOf(AndroidVideoCodec.H264)
            AndroidVideoCodec.AV1 -> emptyList()
        }
        candidates.forEach { codec ->
            capabilities.hardwareCodecs[codec]?.let { name ->
                return AndroidCodecSelection(
                    codec = codec,
                    codecName = name,
                    hardwareAccelerated = true,
                    fallback = codec != preferred,
                    softwareFallback = false,
                )
            }
        }
        if (allowSoftwareFallback) {
            candidates.forEach { codec ->
                capabilities.softwareCodecs[codec]?.let { name ->
                    return AndroidCodecSelection(
                        codec = codec,
                        codecName = name,
                        hardwareAccelerated = false,
                        fallback = codec != preferred,
                        softwareFallback = true,
                    )
                }
            }
        }
        return null
    }
}

data class AndroidDisplayCaptureConfiguration(
    val preferredCodec: AndroidVideoCodec = AndroidVideoCodec.HEVC,
    val framesPerSecond: Int = 30,
    val keyframeIntervalSeconds: Int = 2,
    val averageBitRate: Int = 8_000_000,
    val maximumDimension: Int = 4096,
    val allowSoftwareFallback: Boolean = true,
) {
    fun validate(): AndroidDisplayCaptureConfiguration {
        if (framesPerSecond !in 1..60) {
            throw AndroidDisplayException(
                AndroidDisplayErrorCode.INVALID_CONFIGURATION,
                "Display frame rate must be between 1 and 60 fps.",
            )
        }
        if (keyframeIntervalSeconds !in 1..30) {
            throw AndroidDisplayException(
                AndroidDisplayErrorCode.INVALID_CONFIGURATION,
                "Display keyframe interval must be between 1 and 30 seconds.",
            )
        }
        if (averageBitRate !in 100_000..50_000_000) {
            throw AndroidDisplayException(
                AndroidDisplayErrorCode.INVALID_CONFIGURATION,
                "Display bitrate must be between 100 kbps and 50 Mbps.",
            )
        }
        if (maximumDimension !in 16..8192) {
            throw AndroidDisplayException(
                AndroidDisplayErrorCode.INVALID_CONFIGURATION,
                "Display maximum dimension must be between 16 and 8192.",
            )
        }
        return this
    }
}

data class AndroidDisplayCaptureSize(
    val width: Int,
    val height: Int,
    val densityDpi: Int,
) {
    fun validate(maximumDimension: Int): AndroidDisplayCaptureSize {
        if (width !in 16..maximumDimension || height !in 16..maximumDimension) {
            throw AndroidDisplayException(
                AndroidDisplayErrorCode.INVALID_SIZE,
                "Display dimensions must be between 16 and $maximumDimension pixels.",
            )
        }
        if (densityDpi !in 1..1000) {
            throw AndroidDisplayException(
                AndroidDisplayErrorCode.INVALID_SIZE,
                "Display density must be between 1 and 1000 dpi.",
            )
        }
        return this
    }
}

data class AndroidDisplayStreamMetrics(
    val encodedFrames: Long = 0,
    val keyFrames: Long = 0,
    val encodedBytes: Long = 0,
)

data class EncodedAndroidDisplayFrame(
    val sequence: Long,
    val timestampMicros: Long,
    val width: Int,
    val height: Int,
    val codec: AndroidVideoCodec,
    val keyFrame: Boolean,
    val data: ByteArray,
    val codecConfiguration: ByteArray?,
)

data class AndroidDisplayStreamSnapshot(
    val state: AndroidDisplayCaptureState,
    val codec: AndroidVideoCodec?,
    val codecName: String?,
    val hardwareAccelerated: Boolean,
    val fallback: Boolean,
    val softwareFallback: Boolean,
    val width: Int?,
    val height: Int?,
    val metrics: AndroidDisplayStreamMetrics,
    val lastError: String?,
)

class AndroidMediaCodecStream(
    private val capabilities: AndroidVideoCapabilities = AndroidVideoCapabilities.detect(),
) {
    private val lock = Any()
    private var state = AndroidDisplayCaptureState.IDLE
    private var selected: AndroidCodecSelection? = null
    private var width = 0
    private var height = 0
    private var metrics = AndroidDisplayStreamMetrics()
    private var codecConfiguration: ByteArray? = null
    private var sequence = 0L
    private var lastError: String? = null
    private var onFrame: ((EncodedAndroidDisplayFrame) -> Unit)? = null
    private var onError: ((AndroidDisplayException) -> Unit)? = null

    private var activeCodec: MediaCodec? = null
    private var activeInputSurface: Surface? = null
    private var activeVirtualDisplay: VirtualDisplay? = null
    private var activeProjection: MediaProjection? = null
    private var activeProjectionCallback: MediaProjection.Callback? = null
    private var activeThread: HandlerThread? = null

    fun snapshot(): AndroidDisplayStreamSnapshot = synchronized(lock) {
        AndroidDisplayStreamSnapshot(
            state = state,
            codec = selected?.codec,
            codecName = selected?.codecName,
            hardwareAccelerated = selected?.hardwareAccelerated == true,
            fallback = selected?.fallback == true,
            softwareFallback = selected?.softwareFallback == true,
            width = width.takeIf { it > 0 },
            height = height.takeIf { it > 0 },
            metrics = metrics,
            lastError = lastError,
        )
    }

    fun start(
        projection: MediaProjection,
        size: AndroidDisplayCaptureSize,
        configuration: AndroidDisplayCaptureConfiguration = AndroidDisplayCaptureConfiguration(),
        onFrame: (EncodedAndroidDisplayFrame) -> Unit = {},
        onError: (AndroidDisplayException) -> Unit = {},
    ) {
        configuration.validate()
        size.validate(configuration.maximumDimension)
        val selection = AndroidCodecSelector.select(
            capabilities = capabilities,
            preferred = configuration.preferredCodec,
            allowSoftwareFallback = configuration.allowSoftwareFallback,
        ) ?: throw AndroidDisplayException(
            AndroidDisplayErrorCode.CODEC_UNSUPPORTED,
            "No supported display encoder is available for ${configuration.preferredCodec.wire}.",
        )

        synchronized(lock) {
            if (state == AndroidDisplayCaptureState.STARTING ||
                state == AndroidDisplayCaptureState.RUNNING
            ) {
                throw AndroidDisplayException(
                    AndroidDisplayErrorCode.ALREADY_RUNNING,
                    "A display stream is already running.",
                )
            }
            state = AndroidDisplayCaptureState.STARTING
            selected = selection
            width = size.width
            height = size.height
            metrics = AndroidDisplayStreamMetrics()
            codecConfiguration = null
            sequence = 0
            lastError = null
            this.onFrame = onFrame
            this.onError = onError
        }

        try {
            val format = MediaFormat.createVideoFormat(
                selection.codec.mimeType,
                size.width,
                size.height,
            ).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
                )
                setInteger(MediaFormat.KEY_BIT_RATE, configuration.averageBitRate)
                setInteger(MediaFormat.KEY_FRAME_RATE, configuration.framesPerSecond)
                setInteger(
                    MediaFormat.KEY_I_FRAME_INTERVAL,
                    configuration.keyframeIntervalSeconds,
                )
            }
            val mediaCodec = try {
                MediaCodec.createByCodecName(selection.codecName)
            } catch (error: Exception) {
                throw AndroidDisplayException(
                    AndroidDisplayErrorCode.ENCODER_UNAVAILABLE,
                    "The selected display encoder could not be created.",
                    error,
                )
            }
            synchronized(lock) { activeCodec = mediaCodec }

            val thread = HandlerThread("AirDeskDisplayEncoder").apply { start() }
            val handler = Handler(thread.looper)
            synchronized(lock) { activeThread = thread }

            mediaCodec.setCallback(createCodecCallback(), handler)
            mediaCodec.configure(
                format,
                null,
                null,
                MediaCodec.CONFIGURE_FLAG_ENCODE,
            )
            val inputSurface = mediaCodec.createInputSurface()
            synchronized(lock) {
                activeInputSurface = inputSurface
                activeProjection = projection
            }

            val projectionCallback = object : MediaProjection.Callback() {
                override fun onStop() {
                    fail(
                        AndroidDisplayException(
                            AndroidDisplayErrorCode.PROJECTION_STOPPED,
                            "Screen capture permission was stopped.",
                        ),
                    )
                }
            }
            synchronized(lock) { activeProjectionCallback = projectionCallback }
            projection.registerCallback(projectionCallback, handler)
            mediaCodec.start()

            val display: VirtualDisplay? = try {
                projection.createVirtualDisplay(
                    "AirDesk Display",
                    size.width,
                    size.height,
                    size.densityDpi,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    inputSurface,
                    null,
                    handler,
                )
            } catch (error: SecurityException) {
                throw AndroidDisplayException(
                    AndroidDisplayErrorCode.PROJECTION_UNAVAILABLE,
                    "Screen capture projection is unavailable without an active capture service.",
                    error,
                )
            } catch (error: Exception) {
                throw AndroidDisplayException(
                    AndroidDisplayErrorCode.VIRTUAL_DISPLAY_FAILED,
                    "The virtual display could not be created.",
                    error,
                )
            } ?: throw AndroidDisplayException(
                AndroidDisplayErrorCode.VIRTUAL_DISPLAY_FAILED,
                "The virtual display could not be created.",
            )

            synchronized(lock) {
                activeVirtualDisplay = display
                state = AndroidDisplayCaptureState.RUNNING
            }
        } catch (error: AndroidDisplayException) {
            releaseResources()
            synchronized(lock) {
                state = AndroidDisplayCaptureState.FAILED
                lastError = error.message
            }
            throw error
        } catch (error: Exception) {
            val typed = AndroidDisplayException(
                AndroidDisplayErrorCode.ENCODER_CONFIGURATION_FAILED,
                "The display encoder rejected the capture configuration.",
                error,
            )
            releaseResources()
            synchronized(lock) {
                state = AndroidDisplayCaptureState.FAILED
                lastError = typed.message
            }
            throw typed
        }
    }

    fun stop() {
        synchronized(lock) {
            if (state == AndroidDisplayCaptureState.IDLE ||
                state == AndroidDisplayCaptureState.STOPPED
            ) {
                return
            }
            state = AndroidDisplayCaptureState.STOPPED
        }
        releaseResources()
    }

    private fun createCodecCallback(): MediaCodec.Callback =
        object : MediaCodec.Callback() {
            override fun onInputBufferAvailable(codec: MediaCodec, index: Int) = Unit

            override fun onOutputBufferAvailable(
                codec: MediaCodec,
                index: Int,
                info: MediaCodec.BufferInfo,
            ) {
                try {
                    val buffer = codec.getOutputBuffer(index) ?: return
                    if (info.size > 0 &&
                        info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0
                    ) {
                        if (info.offset < 0 ||
                            info.size < 0 ||
                            info.offset + info.size > buffer.capacity()
                        ) {
                            throw AndroidDisplayException(
                                AndroidDisplayErrorCode.ENCODER_FAILURE,
                                "The display encoder produced an invalid output buffer.",
                            )
                        }
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        val data = ByteArray(info.size)
                        buffer.get(data)
                        val frame = synchronized(lock) {
                            if (state != AndroidDisplayCaptureState.RUNNING) return
                            val codecKind = selected?.codec ?: return
                            val keyFrame = info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0
                            sequence += 1
                            metrics = metrics.copy(
                                encodedFrames = metrics.encodedFrames + 1,
                                keyFrames = metrics.keyFrames + if (keyFrame) 1 else 0,
                                encodedBytes = metrics.encodedBytes + info.size,
                            )
                            EncodedAndroidDisplayFrame(
                                sequence = sequence,
                                timestampMicros = info.presentationTimeUs,
                                width = width,
                                height = height,
                                codec = codecKind,
                                keyFrame = keyFrame,
                                data = data,
                                codecConfiguration = codecConfiguration,
                            )
                        }
                        runCatching { onFrame?.invoke(frame) }
                            .onFailure { error ->
                                fail(
                                    AndroidDisplayException(
                                        AndroidDisplayErrorCode.ENCODER_FAILURE,
                                        "The display frame consumer failed.",
                                        error,
                                    ),
                                )
                            }
                    }
                } catch (error: AndroidDisplayException) {
                    fail(error)
                } catch (error: Exception) {
                    fail(
                        AndroidDisplayException(
                            AndroidDisplayErrorCode.ENCODER_FAILURE,
                            "The display encoder failed while producing a frame.",
                            error,
                        ),
                    )
                } finally {
                    runCatching { codec.releaseOutputBuffer(index, false) }
                }
            }

            override fun onError(codec: MediaCodec, error: MediaCodec.CodecException) {
                fail(
                    AndroidDisplayException(
                        AndroidDisplayErrorCode.ENCODER_FAILURE,
                        "The display encoder reported a failure.",
                        error,
                    ),
                )
            }

            override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
                synchronized(lock) {
                    codecConfiguration = readCodecConfiguration(format)
                }
            }
        }

    private fun fail(error: AndroidDisplayException) {
        val callback: ((AndroidDisplayException) -> Unit)?
        synchronized(lock) {
            if (state == AndroidDisplayCaptureState.IDLE ||
                state == AndroidDisplayCaptureState.STOPPED ||
                state == AndroidDisplayCaptureState.FAILED
            ) {
                return
            }
            state = AndroidDisplayCaptureState.FAILED
            lastError = error.message
            callback = onError
        }
        releaseResources()
        runCatching { callback?.invoke(error) }
    }

    private fun releaseResources() {
        val codec: MediaCodec?
        val inputSurface: Surface?
        val virtualDisplay: VirtualDisplay?
        val projection: MediaProjection?
        val projectionCallback: MediaProjection.Callback?
        val thread: HandlerThread?
        synchronized(lock) {
            codec = activeCodec
            inputSurface = activeInputSurface
            virtualDisplay = activeVirtualDisplay
            projection = activeProjection
            projectionCallback = activeProjectionCallback
            thread = activeThread
            activeCodec = null
            activeInputSurface = null
            activeVirtualDisplay = null
            activeProjection = null
            activeProjectionCallback = null
            activeThread = null
        }

        runCatching { virtualDisplay?.release() }
        runCatching {
            if (projection != null && projectionCallback != null) {
                projection.unregisterCallback(projectionCallback)
            }
        }
        runCatching { inputSurface?.release() }
        runCatching { codec?.stop() }
        runCatching { codec?.release() }
        thread?.quitSafely()
    }

    private fun readCodecConfiguration(format: MediaFormat): ByteArray? {
        val csd0 = copyBuffer(format, "csd-0")
        val csd1 = copyBuffer(format, "csd-1")
        val total = (csd0?.size ?: 0) + (csd1?.size ?: 0)
        if (total == 0) return null
        return ByteArray(total).also { target ->
            var offset = 0
            listOfNotNull(csd0, csd1).forEach { source ->
                source.copyInto(target, offset)
                offset += source.size
            }
        }
    }

    private fun copyBuffer(format: MediaFormat, key: String): ByteArray? {
        val source = runCatching { format.getByteBuffer(key) }.getOrNull() ?: return null
        val duplicate = source.duplicate()
        duplicate.rewind()
        val bytes = ByteArray(duplicate.remaining())
        duplicate.get(bytes)
        return bytes
    }
}
