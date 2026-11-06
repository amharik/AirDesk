package com.airdesk.android.protocol

import AirDesk.Protocol.CapabilityDescriptor
import AirDesk.Protocol.ControlHeader
import AirDesk.Protocol.DeviceIdentity
import AirDesk.Protocol.Envelope
import AirDesk.Protocol.FabricPayload
import AirDesk.Protocol.PairingOffer
import com.google.flatbuffers.FlatBufferBuilder
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest

object AdfpProtocol {
    const val FILE_IDENTIFIER = "ADEN"
    const val VERSION: UInt = 1u
    const val FLATBUFFERS_RUNTIME_VERSION = "25.12.19"
    const val MAX_ENVELOPE_BYTES = 1024 * 1024

    private const val MIN_BUFFER_BYTES = 8

    fun versionLabel(): String = "ADFP envelope v$VERSION ($FILE_IDENTIFIER)"

    fun encodePairingOffer(
        header: AdfpControlHeader,
        offer: AdfpPairingOffer,
        version: UInt = VERSION,
    ): ByteArray = encode(
        version = version,
        header = header,
        payloadType = FabricPayload.PairingOffer,
        payload = ::buildPairingOffer,
        value = offer,
    )

    fun encodeDeviceIdentity(
        header: AdfpControlHeader,
        identity: AdfpDeviceIdentity,
        version: UInt = VERSION,
    ): ByteArray = encode(
        version = version,
        header = header,
        payloadType = FabricPayload.DeviceIdentity,
        payload = ::buildDeviceIdentity,
        value = identity,
    )

    fun encodeCapabilityDescriptor(
        header: AdfpControlHeader,
        descriptor: AdfpCapabilityDescriptor,
        version: UInt = VERSION,
    ): ByteArray = encode(
        version = version,
        header = header,
        payloadType = FabricPayload.CapabilityDescriptor,
        payload = ::buildCapabilityDescriptor,
        value = descriptor,
    )

    private fun <T> encode(
        version: UInt,
        header: AdfpControlHeader,
        payloadType: UByte,
        payload: (FlatBufferBuilder, T) -> Int,
        value: T,
    ): ByteArray {
        val builder = FlatBufferBuilder(1024)
        val payloadOffset = payload(builder, value)
        val headerOffset = buildControlHeader(builder, header)

        Envelope.startEnvelope(builder)
        Envelope.addVersion(builder, version)
        Envelope.addHeader(builder, headerOffset)
        Envelope.addFabricPayloadType(builder, payloadType)
        Envelope.addFabricPayload(builder, payloadOffset)
        val root = Envelope.endEnvelope(builder)
        Envelope.finishEnvelopeBuffer(builder, root)

        val bytes = builder.sizedByteArray()
        if (bytes.size > MAX_ENVELOPE_BYTES) {
            throw AdfpException(
                AdfpError.OVERSIZED,
                "canonical ADFP envelope is ${bytes.size} bytes; limit is $MAX_ENVELOPE_BYTES",
            )
        }
        return bytes
    }

    private fun buildControlHeader(builder: FlatBufferBuilder, header: AdfpControlHeader): Int =
        ControlHeader.createControlHeader(
            builder = builder,
            messageIdOffset = builder.createString(header.messageId),
            senderDeviceIdOffset = builder.createString(header.senderDeviceId),
            senderRole = header.senderRole,
            correlationIdOffset = header.correlationId.stringOffset(builder),
            idempotencyKeyOffset = header.idempotencyKey.stringOffset(builder),
            expiresAt = header.expiresAtEpochMillis,
            cancellationIdOffset = header.cancellationId.stringOffset(builder),
        )

    private fun buildDeviceIdentity(builder: FlatBufferBuilder, identity: AdfpDeviceIdentity): Int =
        DeviceIdentity.createDeviceIdentity(
            builder = builder,
            version = identity.version,
            kind = identity.kind,
            deviceIdOffset = builder.createString(identity.deviceId),
            publicKeyOffset = builder.createString(identity.publicKey),
            nonceOffset = builder.createByteVector(identity.nonce),
            expiresAt = identity.expiresAtEpochMillis,
            channelBindingKind = identity.channelBindingKind,
            channelBindingValueOffset = identity.channelBindingValue.stringOffset(builder),
            capabilitiesOffset = builder.createStringVector(identity.capabilities),
        )

    private fun buildPairingOffer(builder: FlatBufferBuilder, offer: AdfpPairingOffer): Int {
        val identityOffset = buildDeviceIdentity(builder, offer.identity)
        return PairingOffer.createPairingOffer(
            builder = builder,
            identityOffset = identityOffset,
            offerNonceOffset = builder.createByteVector(offer.offerNonce),
            expiresAt = offer.expiresAtEpochMillis,
            channelBindingKind = offer.channelBindingKind,
            channelBindingValueOffset = offer.channelBindingValue.stringOffset(builder),
            capabilitiesOffset = builder.createStringVector(offer.capabilities),
        )
    }

    private fun buildCapabilityDescriptor(
        builder: FlatBufferBuilder,
        descriptor: AdfpCapabilityDescriptor,
    ): Int = CapabilityDescriptor.createCapabilityDescriptor(
        builder = builder,
        capUriOffset = builder.createString(descriptor.capUri),
        version = descriptor.version,
        providerDeviceIdOffset = builder.createString(descriptor.providerDeviceId),
        availability = descriptor.availability,
        authorization = descriptor.authorization,
        permissionsOffset = builder.createStringVector(descriptor.permissions),
        executionOffset = descriptor.execution.stringOffset(builder),
        transportOffset = descriptor.transport.stringOffset(builder),
        constraintsOffset = descriptor.constraints.stringOffset(builder),
    )

    private fun String?.stringOffset(builder: FlatBufferBuilder): Int =
        if (this == null) 0 else builder.createString(this)

    private fun FlatBufferBuilder.createStringVector(values: List<String>): Int {
        if (values.isEmpty()) return 0
        val offsets = IntArray(values.size) { createString(values[it]) }
        startVector(4, offsets.size, 4)
        for (index in offsets.indices.reversed()) addOffset(offsets[index])
        return endVector()
    }

    fun decode(bytes: ByteArray): AdfpEnvelope {
        if (bytes.isEmpty()) {
            throw AdfpException(AdfpError.EMPTY, "ADFP envelope is empty")
        }
        if (bytes.size > MAX_ENVELOPE_BYTES) {
            throw AdfpException(
                AdfpError.OVERSIZED,
                "ADFP envelope is ${bytes.size} bytes; limit is $MAX_ENVELOPE_BYTES",
            )
        }
        if (bytes.size < MIN_BUFFER_BYTES) {
            throw AdfpException(AdfpError.TRUNCATED, "ADFP envelope is shorter than a FlatBuffers root")
        }
        if (!hasFileIdentifier(bytes)) {
            throw AdfpException(
                AdfpError.WRONG_FILE_IDENTIFIER,
                "ADFP envelope file identifier must be $FILE_IDENTIFIER",
            )
        }
        validateRootTable(bytes)

        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        return try {
            decodeEnvelope(Envelope.getRootAsEnvelope(buffer))
        } catch (error: AdfpException) {
            throw error
        } catch (error: Exception) {
            throw AdfpException(AdfpError.MALFORMED, "malformed ADFP envelope", error)
        }
    }

    private fun decodeEnvelope(envelope: Envelope): AdfpEnvelope {
        if (envelope.version != VERSION) {
            throw AdfpException(
                AdfpError.WRONG_VERSION,
                "unsupported ADFP envelope version ${envelope.version}; expected $VERSION",
            )
        }
        val header = envelope.header?.let(::readHeader)
            ?: throw AdfpException(AdfpError.MALFORMED, "ADFP envelope is missing a ControlHeader")

        val payload = when (val type = envelope.fabricPayloadType) {
            FabricPayload.PairingOffer -> {
                val offer = envelope.fabricPayload(PairingOffer()) as? PairingOffer
                    ?: throw AdfpException(AdfpError.MALFORMED, "PairingOffer payload is missing")
                AdfpPayload.PairingOffer(readPairingOffer(offer))
            }
            FabricPayload.DeviceIdentity -> {
                val identity = envelope.fabricPayload(DeviceIdentity()) as? DeviceIdentity
                    ?: throw AdfpException(AdfpError.MALFORMED, "DeviceIdentity payload is missing")
                AdfpPayload.Identity(readIdentity(identity))
            }
            FabricPayload.CapabilityDescriptor -> {
                val descriptor = envelope.fabricPayload(CapabilityDescriptor()) as? CapabilityDescriptor
                    ?: throw AdfpException(AdfpError.MALFORMED, "CapabilityDescriptor payload is missing")
                AdfpPayload.CapabilityDescriptor(readCapabilityDescriptor(descriptor))
            }
            else -> throw AdfpException(
                AdfpError.UNSUPPORTED_PAYLOAD,
                "unsupported ADFP fabric payload type $type",
            )
        }
        return AdfpEnvelope(envelope.version, header, payload)
    }

    private fun readHeader(header: ControlHeader): AdfpControlHeader = AdfpControlHeader(
        messageId = requiredString(header.messageId, "ControlHeader.messageId", 128),
        senderDeviceId = requiredString(header.senderDeviceId, "ControlHeader.senderDeviceId", 128),
        senderRole = header.senderRole,
        correlationId = optionalString(header.correlationId, "ControlHeader.correlationId", 128),
        idempotencyKey = optionalString(header.idempotencyKey, "ControlHeader.idempotencyKey", 128),
        expiresAtEpochMillis = header.expiresAt,
        cancellationId = optionalString(header.cancellationId, "ControlHeader.cancellationId", 128),
    )

    private fun readIdentity(identity: DeviceIdentity): AdfpDeviceIdentity = AdfpDeviceIdentity(
        version = identity.version,
        kind = identity.kind,
        deviceId = requiredString(identity.deviceId, "DeviceIdentity.deviceId", 128),
        publicKey = requiredString(identity.publicKey, "DeviceIdentity.publicKey", 4096),
        nonce = identity.nonceBytes(),
        expiresAtEpochMillis = identity.expiresAt,
        channelBindingKind = identity.channelBindingKind,
        channelBindingValue = optionalString(
            identity.channelBindingValue,
            "DeviceIdentity.channelBindingValue",
            512,
        ),
        capabilities = stringVector("DeviceIdentity.capabilities", identity.capabilitiesLength) {
            identity.capabilities(it)
        },
    )

    private fun readPairingOffer(offer: PairingOffer): AdfpPairingOffer {
        val identity = offer.identity?.let(::readIdentity)
            ?: throw AdfpException(AdfpError.MALFORMED, "PairingOffer is missing a DeviceIdentity")
        return AdfpPairingOffer(
            identity = identity,
            offerNonce = offer.offerNonceBytes(),
            expiresAtEpochMillis = offer.expiresAt,
            channelBindingKind = offer.channelBindingKind,
            channelBindingValue = optionalString(
                offer.channelBindingValue,
                "PairingOffer.channelBindingValue",
                512,
            ),
            capabilities = stringVector("PairingOffer.capabilities", offer.capabilitiesLength) {
                offer.capabilities(it)
            },
        )
    }

    private fun readCapabilityDescriptor(descriptor: CapabilityDescriptor): AdfpCapabilityDescriptor =
        AdfpCapabilityDescriptor(
            capUri = requiredString(
                descriptor.capUri,
                "CapabilityDescriptor.capUri",
                256,
            ),
            version = descriptor.version,
            providerDeviceId = requiredString(
                descriptor.providerDeviceId,
                "CapabilityDescriptor.providerDeviceId",
                128,
            ),
            availability = descriptor.availability,
            authorization = descriptor.authorization,
            permissions = stringVector(
                "CapabilityDescriptor.permissions",
                descriptor.permissionsLength,
            ) { descriptor.permissions(it) },
            execution = optionalString(
                descriptor.execution,
                "CapabilityDescriptor.execution",
                128,
            ),
            transport = optionalString(
                descriptor.transport,
                "CapabilityDescriptor.transport",
                128,
            ),
            constraints = optionalString(
                descriptor.constraints,
                "CapabilityDescriptor.constraints",
                4096,
            ),
        )

    private fun DeviceIdentity.nonceBytes(): ByteArray =
        ByteArray(nonceLength) { nonce(it).toByte() }

    private fun PairingOffer.offerNonceBytes(): ByteArray =
        ByteArray(offerNonceLength) { offerNonce(it).toByte() }

    private fun stringVector(
        field: String,
        length: Int,
        value: (Int) -> String?,
    ): List<String> {
        if (length > 256) {
            throw AdfpException(AdfpError.MALFORMED, "$field has too many entries")
        }
        return List(length) { index ->
            value(index) ?: throw AdfpException(AdfpError.MALFORMED, "$field contains a null entry")
        }
    }

    private fun requiredString(value: String?, field: String, maxBytes: Int): String {
        val result = value
            ?: throw AdfpException(AdfpError.MALFORMED, "$field is missing")
        if (result.toByteArray(Charsets.UTF_8).size > maxBytes) {
            throw AdfpException(AdfpError.MALFORMED, "$field exceeds $maxBytes bytes")
        }
        return result
    }

    private fun optionalString(value: String?, field: String, maxBytes: Int): String? {
        if (value == null) return null
        if (value.toByteArray(Charsets.UTF_8).size > maxBytes) {
            throw AdfpException(AdfpError.MALFORMED, "$field exceeds $maxBytes bytes")
        }
        return value
    }

    private fun hasFileIdentifier(bytes: ByteArray): Boolean {
        val identifier = FILE_IDENTIFIER.toByteArray(Charsets.US_ASCII)
        return bytes[4] == identifier[0] &&
            bytes[5] == identifier[1] &&
            bytes[6] == identifier[2] &&
            bytes[7] == identifier[3]
    }

    private fun validateRootTable(bytes: ByteArray) {
        val root = readInt(bytes, 0)
        if (root < MIN_BUFFER_BYTES || root + 4 > bytes.size) {
            throw AdfpException(AdfpError.TRUNCATED, "ADFP envelope root offset is out of range")
        }
        val vtableStart = root - readInt(bytes, root)
        if (vtableStart < 0 || vtableStart + 4 > bytes.size) {
            throw AdfpException(AdfpError.TRUNCATED, "ADFP envelope vtable is out of range")
        }
        val vtableSize = readShort(bytes, vtableStart)
        if (vtableSize < 4 || vtableStart + vtableSize > bytes.size) {
            throw AdfpException(AdfpError.TRUNCATED, "ADFP envelope vtable is truncated")
        }
    }

    private fun readInt(bytes: ByteArray, offset: Int): Int =
        (bytes[offset].toInt() and 0xff) or
            ((bytes[offset + 1].toInt() and 0xff) shl 8) or
            ((bytes[offset + 2].toInt() and 0xff) shl 16) or
            ((bytes[offset + 3].toInt() and 0xff) shl 24)

    private fun readShort(bytes: ByteArray, offset: Int): Int =
        (bytes[offset].toInt() and 0xff) or ((bytes[offset + 1].toInt() and 0xff) shl 8)

    fun sha256(bytes: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(bytes)

    fun sha256Hex(bytes: ByteArray): String = hexLowercase(sha256(bytes))

    fun hexLowercase(bytes: ByteArray): String {
        val digits = "0123456789abcdef"
        val out = CharArray(bytes.size * 2)
        bytes.forEachIndexed { index, byte ->
            val value = byte.toInt() and 0xff
            out[index * 2] = digits[value ushr 4]
            out[index * 2 + 1] = digits[value and 0x0f]
        }
        return String(out)
    }

    fun selfTest(canonical: CanonicalPairingOffer): AdfpSelfTestResult = try {
        val decoded = decode(canonical.bytes)
        val payload = decoded.payload as? AdfpPayload.PairingOffer
            ?: return AdfpSelfTestResult(false, "fail: unexpected payload type")
        val reencoded = encodePairingOffer(decoded.header, payload.offer)
        val stable = reencoded.contentEquals(canonical.bytes) &&
            sha256Hex(reencoded) == canonical.sha256Hex
        AdfpSelfTestResult(
            ok = stable,
            detail = if (stable) {
                "pass: decoded and re-encoded ${canonical.bytes.size} bytes with a stable hash"
            } else {
                "fail: canonical re-encode changed the envelope bytes or hash"
            },
        )
    } catch (error: Exception) {
        AdfpSelfTestResult(false, "fail: ${error.message ?: error::class.java.simpleName}")
    }
}
