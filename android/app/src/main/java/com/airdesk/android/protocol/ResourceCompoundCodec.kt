package com.airdesk.android.protocol

import AirDesk.Protocol.BlobAlgorithm as FlatBlobAlgorithm
import AirDesk.Protocol.BlobHandle as FlatBlobHandle
import AirDesk.Protocol.Qid as FlatQid
import AirDesk.Protocol.ResourceCompoundRequest as FlatResourceCompoundRequest
import AirDesk.Protocol.ResourceCompoundResult as FlatResourceCompoundResult
import AirDesk.Protocol.ResourceOpCode as FlatResourceOpCode
import AirDesk.Protocol.ResourceReadResult as FlatResourceReadResult
import AirDesk.Protocol.ResourceRpc as FlatResourceRpc
import AirDesk.Protocol.ResourceRpcPayload as FlatResourceRpcPayload
import AirDesk.Protocol.ResourceStat as FlatResourceStat
import com.google.flatbuffers.FlatBufferBuilder
import java.nio.ByteBuffer

object ResourceCompoundCodec {
    const val INLINE_LIMIT = 64 * 1024
    const val BLOB_HANDLE_VERSION = 1u
    const val BLAKE3_DIGEST_BYTES = 32
    const val MAX_PATH_SEGMENTS = 32
    const val MAX_PATH_SEGMENT_BYTES = 255

    private val defaultQid = AdfpQid(type = 0u, version = 0u, path = 0uL)

    fun validatePathSegments(wnames: List<String>) {
        if (wnames.size > MAX_PATH_SEGMENTS) {
            throw AdfpException(AdfpError.INVALID_PATH, "too many path segments")
        }
        for (name in wnames) {
            if (name.isEmpty() ||
                name.toByteArray(Charsets.UTF_8).size > MAX_PATH_SEGMENT_BYTES ||
                name == "." ||
                name == ".." ||
                name.contains('/')
            ) {
                throw AdfpException(AdfpError.INVALID_PATH, "invalid path segment")
            }
        }
    }

    fun validateBlobHandle(handle: AdfpBlobHandle) {
        if (handle.version != BLOB_HANDLE_VERSION) {
            throw AdfpException(
                AdfpError.UNSUPPORTED_BLOB,
                "unsupported blob handle version",
            )
        }
        if (handle.algorithm != FlatBlobAlgorithm.blake3) {
            throw AdfpException(
                AdfpError.UNSUPPORTED_BLOB,
                "unsupported blob digest algorithm",
            )
        }
        if (handle.digest.size != BLAKE3_DIGEST_BYTES) {
            throw AdfpException(
                AdfpError.UNSUPPORTED_BLOB,
                "blake3 digest must be 32 bytes",
            )
        }
        if (handle.length == 0uL) {
            throw AdfpException(AdfpError.UNSUPPORTED_BLOB, "invalid blob length")
        }
    }

    fun validateCompoundRequest(request: AdfpCompoundRequest) {
        validatePathSegments(request.wnames)
    }

    fun validateCompoundResult(result: AdfpCompoundResult) {
        if (result.data.size > INLINE_LIMIT) {
            throw AdfpException(
                AdfpError.INLINE_TOO_LARGE,
                "inline result exceeds 64 KiB; return a blob handle",
            )
        }
        if (result.data.isNotEmpty() && result.blob != null) {
            throw AdfpException(
                AdfpError.AMBIGUOUS_PAYLOAD,
                "result cannot carry both inline data and a blob handle",
            )
        }
        result.blob?.let { validateBlobHandle(it) }
    }

    fun validateReadResult(result: AdfpResourcePayload.ReadResult) {
        if (result.data.size > INLINE_LIMIT) {
            throw AdfpException(
                AdfpError.INLINE_TOO_LARGE,
                "inline read result exceeds 64 KiB",
            )
        }
        if (result.data.isNotEmpty() && result.blob != null) {
            throw AdfpException(
                AdfpError.AMBIGUOUS_PAYLOAD,
                "read result cannot carry both data and a blob handle",
            )
        }
        result.blob?.let { validateBlobHandle(it) }
    }

    fun encodeCompoundRequest(request: AdfpCompoundRequest): ByteArray {
        validateCompoundRequest(request)
        val builder = FlatBufferBuilder(1024)
        val payload = writeCompoundRequest(builder, request)
        return finish(
            builder,
            FlatResourceRpcPayload.ResourceCompoundRequest,
            payload,
            FlatResourceOpCode.compound,
        )
    }

    fun decodeCompoundRequest(bytes: ByteArray): AdfpCompoundRequest {
        val rpc = root(bytes)
        if (rpc.opCode != FlatResourceOpCode.compound) {
            throw AdfpException(AdfpError.MALFORMED, "expected compound op code")
        }
        if (rpc.payloadType != FlatResourceRpcPayload.ResourceCompoundRequest) {
            throw AdfpException(AdfpError.MALFORMED, "expected compound request payload")
        }
        val request = rpc.payload(FlatResourceCompoundRequest()) as? FlatResourceCompoundRequest
            ?: throw AdfpException(AdfpError.MALFORMED, "compound request payload is missing")
        return readCompoundRequest(request)
    }

    fun encodeCompoundResult(result: AdfpCompoundResult): ByteArray {
        validateCompoundResult(result)
        val builder = FlatBufferBuilder(1024)
        val payload = writeCompoundResult(builder, result)
        return finish(
            builder,
            FlatResourceRpcPayload.ResourceCompoundResult,
            payload,
            FlatResourceOpCode.compound_result,
        )
    }

    fun decodeCompoundResult(bytes: ByteArray): AdfpCompoundResult {
        val rpc = root(bytes)
        if (rpc.opCode != FlatResourceOpCode.compound_result) {
            throw AdfpException(AdfpError.MALFORMED, "expected compound result op code")
        }
        if (rpc.payloadType != FlatResourceRpcPayload.ResourceCompoundResult) {
            throw AdfpException(AdfpError.MALFORMED, "expected compound result payload")
        }
        val result = rpc.payload(FlatResourceCompoundResult()) as? FlatResourceCompoundResult
            ?: throw AdfpException(AdfpError.MALFORMED, "compound result payload is missing")
        return readCompoundResult(result)
    }

    fun encodeReadResult(result: AdfpResourcePayload.ReadResult): ByteArray {
        validateReadResult(result)
        val builder = FlatBufferBuilder(1024)
        val payload = writeReadResult(builder, result)
        return finish(
            builder,
            FlatResourceRpcPayload.ResourceReadResult,
            payload,
            FlatResourceOpCode.read_result,
        )
    }

    fun decodeReadResult(bytes: ByteArray): AdfpResourcePayload.ReadResult {
        val rpc = root(bytes)
        if (rpc.opCode != FlatResourceOpCode.read_result ||
            rpc.payloadType != FlatResourceRpcPayload.ResourceReadResult
        ) {
            throw AdfpException(AdfpError.MALFORMED, "expected read result payload")
        }
        val result = rpc.payload(FlatResourceReadResult()) as? FlatResourceReadResult
            ?: throw AdfpException(AdfpError.MALFORMED, "read result payload is missing")
        return readReadResult(result)
    }

    internal fun writeCompoundRequest(
        builder: FlatBufferBuilder,
        request: AdfpCompoundRequest,
    ): Int {
        validateCompoundRequest(request)
        val nameOffsets = IntArray(request.wnames.size) {
            builder.createString(request.wnames[it])
        }
        val namesOffset = if (nameOffsets.isEmpty()) {
            0
        } else {
            FlatResourceCompoundRequest.createWnamesVector(builder, nameOffsets)
        }
        return FlatResourceCompoundRequest.createResourceCompoundRequest(
            builder = builder,
            requestId = request.requestId,
            fid = request.fid,
            newFid = request.newFid,
            wnamesOffset = namesOffset,
            openMode = request.openMode,
            readOffset = request.readOffset,
            readCount = request.readCount,
            clunk = request.clunk,
        )
    }

    internal fun readCompoundRequest(table: FlatResourceCompoundRequest): AdfpCompoundRequest {
        val wnames = List(table.wnamesLength) { index ->
            table.wnames(index)
                ?: throw AdfpException(AdfpError.INVALID_PATH, "invalid path segment")
        }
        val request = AdfpCompoundRequest(
            requestId = table.requestId,
            fid = table.fid,
            newFid = table.newFid,
            wnames = wnames,
            openMode = table.openMode,
            readOffset = table.readOffset,
            readCount = table.readCount,
            clunk = table.clunk,
        )
        validateCompoundRequest(request)
        return request
    }

    internal fun writeCompoundResult(
        builder: FlatBufferBuilder,
        result: AdfpCompoundResult,
    ): Int {
        validateCompoundResult(result)
        val dataOffset = result.data.writeByteVector(builder)
        val blobOffset = result.blob?.let { writeBlobHandle(builder, it) } ?: 0
        val statOffset = result.stat?.let { writeStat(builder, it) } ?: 0
        FlatResourceCompoundResult.startResourceCompoundResult(builder)
        FlatResourceCompoundResult.addRequestId(builder, result.requestId)
        FlatResourceCompoundResult.addStatus(builder, result.status)
        FlatResourceCompoundResult.addQid(builder, (result.qid ?: defaultQid).write(builder))
        FlatResourceCompoundResult.addIounit(builder, result.iounit)
        if (dataOffset != 0) FlatResourceCompoundResult.addData(builder, dataOffset)
        if (blobOffset != 0) FlatResourceCompoundResult.addBlob(builder, blobOffset)
        if (statOffset != 0) FlatResourceCompoundResult.addStat(builder, statOffset)
        FlatResourceCompoundResult.addClunkStatus(builder, result.clunkStatus)
        return FlatResourceCompoundResult.endResourceCompoundResult(builder)
    }

    internal fun readCompoundResult(table: FlatResourceCompoundResult): AdfpCompoundResult {
        if (table.dataLength > INLINE_LIMIT) {
            throw AdfpException(
                AdfpError.INLINE_TOO_LARGE,
                "inline result exceeds 64 KiB; return a blob handle",
            )
        }
        val result = AdfpCompoundResult(
            requestId = table.requestId,
            status = table.status,
            qid = table.qid?.read(),
            iounit = table.iounit,
            data = ByteArray(table.dataLength) { table.data(it).toByte() },
            blob = table.blob?.let { readBlobHandle(it) },
            stat = table.stat?.let { readStat(it) },
            clunkStatus = table.clunkStatus,
        )
        validateCompoundResult(result)
        return result
    }

    internal fun writeReadResult(
        builder: FlatBufferBuilder,
        result: AdfpResourcePayload.ReadResult,
    ): Int {
        validateReadResult(result)
        val dataOffset = result.data.writeByteVector(builder)
        val blobOffset = result.blob?.let { writeBlobHandle(builder, it) } ?: 0
        return FlatResourceReadResult.createResourceReadResult(
            builder,
            dataOffset,
            blobOffset,
        )
    }

    internal fun readReadResult(table: FlatResourceReadResult): AdfpResourcePayload.ReadResult {
        if (table.dataLength > INLINE_LIMIT) {
            throw AdfpException(
                AdfpError.INLINE_TOO_LARGE,
                "inline read result exceeds 64 KiB",
            )
        }
        val result = AdfpResourcePayload.ReadResult(
            data = ByteArray(table.dataLength) { table.data(it).toByte() },
            blob = table.blob?.let { readBlobHandle(it) },
        )
        validateReadResult(result)
        return result
    }

    internal fun writeBlobHandle(
        builder: FlatBufferBuilder,
        handle: AdfpBlobHandle,
    ): Int {
        validateBlobHandle(handle)
        val digestOffset = handle.digest.writeByteVector(builder)
        return FlatBlobHandle.createBlobHandle(
            builder = builder,
            version = handle.version,
            algorithm = handle.algorithm,
            digestOffset = digestOffset,
            length = handle.length,
            expiresAt = handle.expiresAtEpochMillis,
        )
    }

    internal fun readBlobHandle(table: FlatBlobHandle): AdfpBlobHandle {
        val handle = AdfpBlobHandle(
            version = table.version,
            algorithm = table.algorithm,
            digest = ByteArray(table.digestLength) { table.digest(it).toByte() },
            length = table.length,
            expiresAtEpochMillis = table.expiresAt,
        )
        validateBlobHandle(handle)
        return handle
    }

    private fun writeStat(builder: FlatBufferBuilder, stat: AdfpResourceStat): Int {
        val nameOffset = stat.name?.let { builder.createString(it) } ?: 0
        FlatResourceStat.startResourceStat(builder)
        FlatResourceStat.addQid(builder, stat.qid.write(builder))
        FlatResourceStat.addMode(builder, stat.mode)
        FlatResourceStat.addLength(builder, stat.length)
        if (nameOffset != 0) FlatResourceStat.addName(builder, nameOffset)
        FlatResourceStat.addModifiedAt(builder, stat.modifiedAtEpochMillis)
        return FlatResourceStat.endResourceStat(builder)
    }

    private fun readStat(table: FlatResourceStat): AdfpResourceStat = AdfpResourceStat(
        qid = table.qid?.read()
            ?: throw AdfpException(AdfpError.MALFORMED, "ResourceStat.qid is missing"),
        mode = table.mode,
        length = table.length,
        name = table.name,
        modifiedAtEpochMillis = table.modifiedAt,
    )

    private fun root(bytes: ByteArray): FlatResourceRpc {
        if (bytes.size < 8) {
            throw AdfpException(AdfpError.MALFORMED, "resource FlatBuffer is truncated")
        }
        return try {
            FlatResourceRpc.getRootAsResourceRpc(ByteBuffer.wrap(bytes))
        } catch (error: AdfpException) {
            throw error
        } catch (error: Exception) {
            throw AdfpException(AdfpError.MALFORMED, "malformed resource FlatBuffer", error)
        } catch (error: AssertionError) {
            throw AdfpException(AdfpError.MALFORMED, "malformed resource FlatBuffer", error)
        }
    }

    private fun finish(
        builder: FlatBufferBuilder,
        payloadType: UByte,
        payloadOffset: Int,
        opCode: UInt,
    ): ByteArray {
        val root = FlatResourceRpc.createResourceRpc(
            builder = builder,
            payloadType = payloadType,
            payloadOffset = payloadOffset,
            opCode = opCode,
        )
        builder.finish(root)
        return builder.sizedByteArray()
    }

    private fun ByteArray.writeByteVector(builder: FlatBufferBuilder): Int {
        if (isEmpty()) return 0
        builder.startVector(1, size, 1)
        for (index in indices.reversed()) {
            builder.addByte(this[index])
        }
        return builder.endVector()
    }

    private fun AdfpQid.write(builder: FlatBufferBuilder): Int =
        FlatQid.createQid(builder, type, version, path)

    private fun FlatQid.read(): AdfpQid = AdfpQid(type, version, path)
}
