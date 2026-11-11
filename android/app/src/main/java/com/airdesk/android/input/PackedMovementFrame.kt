package com.airdesk.android.input

import java.nio.ByteBuffer
import java.nio.ByteOrder

class PackedMovementException(message: String) : Exception(message)

data class PackedMovementFrame(
    val leaseEpochLow: Int,
    val seq: Long,
    val x: Float,
    val y: Float,
    val buttonMask: Int = 0,
    val modifiers: Int = 0,
) {
    fun encode(): ByteArray {
        if (leaseEpochLow !in 0..0xffff) {
            throw PackedMovementException("leaseEpochLow must be a uint16")
        }
        if (seq !in 0..0xffff_ffffL) {
            throw PackedMovementException("seq must be a uint32")
        }
        if (!x.isFinite() || !y.isFinite() || x !in 0f..1f || y !in 0f..1f) {
            throw PackedMovementException("movement coordinates must be normalized")
        }
        if (buttonMask !in 0..0b111) {
            throw PackedMovementException("buttonMask must fit in three bits")
        }
        if (modifiers !in 0..0b111) {
            throw PackedMovementException("modifiers must fit in three bits")
        }

        return ByteBuffer.allocate(BYTES)
            .order(ByteOrder.LITTLE_ENDIAN)
            .put(MAGIC)
            .put(((buttonMask shl 2) or (modifiers shl 5)).toByte())
            .putShort(leaseEpochLow.toShort())
            .putInt(seq.toInt())
            .putFloat(x)
            .putFloat(y)
            .array()
    }

    companion object {
        const val MAGIC: Byte = 0xa5.toByte()
        const val BYTES = 16
        const val MODIFIER_SHIFT = 1
        const val MODIFIER_OPTION = 1 shl 1
        const val MODIFIER_COMMAND = 1 shl 2

        fun decode(bytes: ByteArray): PackedMovementFrame {
            if (bytes.size != BYTES) {
                throw PackedMovementException("movement frame must be exactly 16 bytes")
            }
            if (bytes[0] != MAGIC) {
                throw PackedMovementException("invalid movement magic")
            }
            val flags = bytes[1].toInt() and 0xff
            if ((flags and 0b11) != 0) {
                throw PackedMovementException("movement frames cannot carry input edges")
            }
            val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            val x = buffer.getFloat(8)
            val y = buffer.getFloat(12)
            if (!x.isFinite() || !y.isFinite() || x !in 0f..1f || y !in 0f..1f) {
                throw PackedMovementException("movement coordinates must be normalized")
            }
            return PackedMovementFrame(
                leaseEpochLow = buffer.getShort(2).toInt() and 0xffff,
                seq = buffer.getInt(4).toLong() and 0xffff_ffffL,
                x = x,
                y = y,
                buttonMask = (flags shr 2) and 0b111,
                modifiers = (flags shr 5) and 0b111,
            )
        }
    }
}
