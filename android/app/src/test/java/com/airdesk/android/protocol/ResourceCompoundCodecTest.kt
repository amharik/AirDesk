package com.airdesk.android.protocol

import AirDesk.Protocol.SenderRole
import com.airdesk.android.fabric.IrohFabricChannel
import java.io.File
import java.util.HexFormat
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class ResourceCompoundCodecTest {
    private val compound = Json.parseToJsonElement(compoundFile().readText()).jsonObject
    private val blobFile = Json.parseToJsonElement(blobFixtureFile().readText()).jsonObject
    private val hex = HexFormat.of()

    @Test
    fun compoundRequestFixtureDecodesAndRoundTrips() {
        val fixture = compound.getValue("request").jsonObject
        val bytes = hex.parseHex(fixture.string("hex"))
        val decoded = ResourceCompoundCodec.decodeCompoundRequest(bytes)

        assertEquals(42uL, decoded.requestId)
        assertEquals(7u, decoded.fid)
        assertEquals(8u, decoded.newFid)
        assertEquals(listOf("documents", "notes.txt"), decoded.wnames)
        assertEquals(0u.toUByte(), decoded.openMode)
        assertEquals(0uL, decoded.readOffset)
        assertEquals(32u, decoded.readCount)
        assertEquals(true, decoded.clunk)

        val reencoded = ResourceCompoundCodec.encodeCompoundRequest(decoded)
        assertRequestEquals(decoded, ResourceCompoundCodec.decodeCompoundRequest(reencoded))
    }

    @Test
    fun inlineCompoundResultFixtureDecodesAndRoundTrips() {
        val fixture = compound.getValue("result").jsonObject
        val decoded = ResourceCompoundCodec.decodeCompoundResult(
            hex.parseHex(fixture.string("hex")),
        )

        assertEquals(42uL, decoded.requestId)
        assertEquals(0u.toUByte(), decoded.status)
        assertEquals(AdfpQid(0u, 3u, 987_654_321uL), decoded.qid)
        assertEquals(65_536u, decoded.iounit)
        assertArrayEquals("hello from compound read\n".toByteArray(), decoded.data)
        assertNull(decoded.blob)
        assertEquals("notes.txt", decoded.stat?.name)
        assertEquals(25uL, decoded.stat?.length)
        assertEquals(1_700_000_000_123uL, decoded.stat?.modifiedAtEpochMillis)
        assertEquals(0u.toUByte(), decoded.clunkStatus)

        val reencoded = ResourceCompoundCodec.encodeCompoundResult(decoded)
        assertResultEquals(decoded, ResourceCompoundCodec.decodeCompoundResult(reencoded))
    }

    @Test
    fun largeCompoundResultReturnsVersionedBlake3Handle() {
        val fixture = compound.getValue("blobResult").jsonObject
        val decoded = ResourceCompoundCodec.decodeCompoundResult(
            hex.parseHex(fixture.string("hex")),
        )

        assertEquals(43uL, decoded.requestId)
        assertEquals(0, decoded.data.size)
        assertNull(decoded.stat)
        val blob = decoded.blob!!
        assertEquals(ResourceCompoundCodec.BLOB_HANDLE_VERSION, blob.version)
        assertEquals(1u.toUByte(), blob.algorithm)
        assertEquals(
            hex.parseHex("af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262").toList(),
            blob.digest.toList(),
        )
        assertEquals(131_072uL, blob.length)
        assertEquals(1_700_000_600_000uL, blob.expiresAtEpochMillis)

        val reencoded = ResourceCompoundCodec.encodeCompoundResult(decoded)
        assertResultEquals(decoded, ResourceCompoundCodec.decodeCompoundResult(reencoded))
    }

    @Test
    fun readResultFixturesDecodeAndRoundTrip() {
        val blobFixture = blobFile.getValue("blob").jsonObject
        val large = ResourceCompoundCodec.decodeReadResult(
            hex.parseHex(blobFixture.string("hex")),
        )
        assertEquals(0, large.data.size)
        assertEquals(131_072uL, large.blob?.length)
        assertReadEquals(
            large,
            ResourceCompoundCodec.decodeReadResult(
                ResourceCompoundCodec.encodeReadResult(large),
            ),
        )

        val smallFixture = blobFile.getValue("smallRead").jsonObject
        val small = ResourceCompoundCodec.decodeReadResult(
            hex.parseHex(smallFixture.string("hex")),
        )
        assertArrayEquals("small payload".toByteArray(), small.data)
        assertNull(small.blob)
        assertReadEquals(
            small,
            ResourceCompoundCodec.decodeReadResult(
                ResourceCompoundCodec.encodeReadResult(small),
            ),
        )
    }

    @Test
    fun rejectsOversizedAmbiguousAndInvalidBlobPayloads() {
        val digest = hex.parseHex(blobFile.getValue("blob").jsonObject.string("digestHex"))
        val blob = AdfpBlobHandle(digest = digest, length = 131_072uL)

        val oversized = assertThrows(AdfpException::class.java) {
            ResourceCompoundCodec.encodeCompoundResult(
                AdfpCompoundResult(
                    requestId = 1uL,
                    data = ByteArray(ResourceCompoundCodec.INLINE_LIMIT + 1),
                ),
            )
        }
        assertEquals(AdfpError.INLINE_TOO_LARGE, oversized.reason)

        val ambiguous = assertThrows(AdfpException::class.java) {
            ResourceCompoundCodec.encodeReadResult(
                AdfpResourcePayload.ReadResult(ByteArray(1) { 1 }, blob),
            )
        }
        assertEquals(AdfpError.AMBIGUOUS_PAYLOAD, ambiguous.reason)

        val shortDigest = assertThrows(AdfpException::class.java) {
            ResourceCompoundCodec.validateBlobHandle(
                AdfpBlobHandle(digest = digest.copyOf(31), length = 1uL),
            )
        }
        assertEquals(AdfpError.UNSUPPORTED_BLOB, shortDigest.reason)

        val unknownAlgorithm = assertThrows(AdfpException::class.java) {
            ResourceCompoundCodec.validateBlobHandle(
                AdfpBlobHandle(digest = digest, length = 1uL, algorithm = 9u),
            )
        }
        assertEquals(AdfpError.UNSUPPORTED_BLOB, unknownAlgorithm.reason)
    }

    @Test
    fun rejectsUnsafePathSegments() {
        val base = AdfpCompoundRequest(
            requestId = 1uL,
            fid = 1u,
            newFid = 2u,
            wnames = listOf(".."),
        )
        val dotdot = assertThrows(AdfpException::class.java) {
            ResourceCompoundCodec.encodeCompoundRequest(base)
        }
        assertEquals(AdfpError.INVALID_PATH, dotdot.reason)

        val slash = assertThrows(AdfpException::class.java) {
            ResourceCompoundCodec.encodeCompoundRequest(base.copy(wnames = listOf("a/b")))
        }
        assertEquals(AdfpError.INVALID_PATH, slash.reason)

        val tooMany = assertThrows(AdfpException::class.java) {
            ResourceCompoundCodec.encodeCompoundRequest(
                base.copy(
                    wnames = List(ResourceCompoundCodec.MAX_PATH_SEGMENTS + 1) { "x" },
                ),
            )
        }
        assertEquals(AdfpError.INVALID_PATH, tooMany.reason)
    }

    @Test
    fun sessionRoundTripsCompoundAndBlobResourcePayloads() {
        val session = AdfpFabricSession()
        val header = AdfpControlHeader(
            messageId = "message-1",
            senderDeviceId = "ad-device:" + "a".repeat(64),
            senderRole = SenderRole.agent,
            expiresAtEpochMillis = 4_102_444_800_000uL,
        )
        val blob = AdfpBlobHandle(
            digest = hex.parseHex("af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"),
            length = 131_072uL,
            expiresAtEpochMillis = 1_700_000_600_000uL,
        )
        val payload = AdfpSessionPayload.Resource(
            AdfpResourceRpc(
                AdfpResourcePayload.CompoundResult(
                    AdfpCompoundResult(
                        requestId = 7uL,
                        qid = AdfpQid(1u, 2u, 3uL),
                        blob = blob,
                    ),
                ),
            ),
        )

        val encoded = session.encode(payload, header)
        val decoded = session.decode(IrohFabricChannel.RESOURCE, encoded)
            as AdfpSessionPayload.Resource
        val result = (decoded.rpc.payload as AdfpResourcePayload.CompoundResult).result

        assertEquals(7uL, result.requestId)
        assertEquals(AdfpQid(1u, 2u, 3uL), result.qid)
        assertArrayEquals(blob.digest, result.blob?.digest)
        assertEquals(131_072uL, result.blob?.length)
    }

    private fun assertRequestEquals(
        expected: AdfpCompoundRequest,
        actual: AdfpCompoundRequest,
    ) {
        assertEquals(expected.requestId, actual.requestId)
        assertEquals(expected.fid, actual.fid)
        assertEquals(expected.newFid, actual.newFid)
        assertEquals(expected.wnames, actual.wnames)
        assertEquals(expected.openMode, actual.openMode)
        assertEquals(expected.readOffset, actual.readOffset)
        assertEquals(expected.readCount, actual.readCount)
        assertEquals(expected.clunk, actual.clunk)
    }

    private fun assertResultEquals(
        expected: AdfpCompoundResult,
        actual: AdfpCompoundResult,
    ) {
        assertEquals(expected.requestId, actual.requestId)
        assertEquals(expected.status, actual.status)
        assertEquals(expected.qid, actual.qid)
        assertEquals(expected.iounit, actual.iounit)
        assertArrayEquals(expected.data, actual.data)
        assertEquals(expected.clunkStatus, actual.clunkStatus)
        assertEquals(expected.stat?.qid, actual.stat?.qid)
        assertEquals(expected.stat?.mode, actual.stat?.mode)
        assertEquals(expected.stat?.length, actual.stat?.length)
        assertEquals(expected.stat?.name, actual.stat?.name)
        assertEquals(expected.stat?.modifiedAtEpochMillis, actual.stat?.modifiedAtEpochMillis)
        assertBlobEquals(expected.blob, actual.blob)
    }

    private fun assertReadEquals(
        expected: AdfpResourcePayload.ReadResult,
        actual: AdfpResourcePayload.ReadResult,
    ) {
        assertArrayEquals(expected.data, actual.data)
        assertBlobEquals(expected.blob, actual.blob)
    }

    private fun assertBlobEquals(expected: AdfpBlobHandle?, actual: AdfpBlobHandle?) {
        if (expected == null || actual == null) {
            assertNull(expected)
            assertNull(actual)
            return
        }
        assertEquals(expected.version, actual.version)
        assertEquals(expected.algorithm, actual.algorithm)
        assertArrayEquals(expected.digest, actual.digest)
        assertEquals(expected.length, actual.length)
        assertEquals(expected.expiresAtEpochMillis, actual.expiresAtEpochMillis)
    }

    private fun JsonObject.string(key: String): String =
        getValue(key).jsonPrimitive.content

    private fun compoundFile(): File =
        fixtureFile("protocol/fixtures/resource-compound/walk-open-read-clunk-v1.json")

    private fun blobFixtureFile(): File =
        fixtureFile("protocol/fixtures/resource-blob/blake3-handle-v1.json")

    private fun fixtureFile(relativePath: String): File {
        var directory = File(System.getProperty("user.dir") ?: ".")
        repeat(6) {
            val candidate = File(directory, relativePath)
            if (candidate.isFile) return candidate
            directory = directory.parentFile ?: return@repeat
        }
        error("could not find $relativePath from ${System.getProperty("user.dir")}")
    }
}
