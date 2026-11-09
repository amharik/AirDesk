package com.airdesk.android.fabric

import java.nio.ByteBuffer
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class IrohFabricFrameTest {
    @Test
    fun reliableFrameMatchesWireFormat() {
        val frame = IrohFabricFrame.encode(IrohFabricChannel.PAIRING, byteArrayOf(1, 2, 3))

        assertEquals(IrohFabricChannel.PAIRING.wire.toByte(), frame[0])
        assertEquals(3, ByteBuffer.wrap(frame, 1, 4).int)
        assertArrayEquals(byteArrayOf(1, 2, 3), frame.copyOfRange(5, frame.size))
    }

    @Test
    fun movementIsNotAReasonableReliableChannel() {
        assertEquals(false, IrohFabricChannel.MOVEMENT.isReliable)
        assertNull(IrohFabricChannel.reliable(IrohFabricChannel.MOVEMENT.wire))
    }

    @Test(expected = IllegalArgumentException::class)
    fun movementCannotBeEncodedAsReliableFrame() {
        IrohFabricFrame.encode(IrohFabricChannel.MOVEMENT, ByteArray(16))
    }
}
