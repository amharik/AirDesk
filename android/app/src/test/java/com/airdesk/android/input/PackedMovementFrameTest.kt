package com.airdesk.android.input

import java.io.File
import java.util.HexFormat
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class PackedMovementFrameTest {
    private val root = Json.parseToJsonElement(fixtureFile().readText()).jsonArray
    private val case = root[0].jsonObject
    private val hex = HexFormat.of()

    @Test
    fun sharedFixtureDecodesAndRoundTrips() {
        val bytes = hex.parseHex(case.getValue("hex").jsonPrimitive.content)
        val expected = case.getValue("expected").jsonObject
        val frame = PackedMovementFrame.decode(bytes)

        assertEquals(expected.getValue("leaseEpochLow").jsonPrimitive.content.toInt(), frame.leaseEpochLow)
        assertEquals(expected.getValue("seq").jsonPrimitive.content.toLong(), frame.seq)
        assertEquals(expected.getValue("x").jsonPrimitive.content.toFloat(), frame.x, 0f)
        assertEquals(expected.getValue("y").jsonPrimitive.content.toFloat(), frame.y, 0f)
        assertEquals(expected.getValue("buttonMask").jsonPrimitive.content.toInt(), frame.buttonMask)
        assertEquals(PackedMovementFrame.MODIFIER_SHIFT, frame.modifiers)
        assertArrayEquals(bytes, frame.encode())
    }

    @Test
    fun malformedFramesAreRejected() {
        assertThrows(PackedMovementException::class.java) {
            PackedMovementFrame.decode(ByteArray(PackedMovementFrame.BYTES))
        }

        val edge = hex.parseHex(case.getValue("hex").jsonPrimitive.content)
        edge[1] = 0b01
        assertThrows(PackedMovementException::class.java) {
            PackedMovementFrame.decode(edge)
        }

        val coordinates = hex.parseHex(case.getValue("hex").jsonPrimitive.content)
        coordinates[8] = 0x00
        coordinates[9] = 0x00
        coordinates[10] = 0x00
        coordinates[11] = 0x40
        assertThrows(PackedMovementException::class.java) {
            PackedMovementFrame.decode(coordinates)
        }

        assertThrows(PackedMovementException::class.java) {
            PackedMovementFrame.decode(ByteArray(PackedMovementFrame.BYTES - 1))
        }
        assertThrows(PackedMovementException::class.java) {
            PackedMovementFrame(0, 0, 0.5f, 0.5f, buttonMask = 8).encode()
        }
    }

    private fun fixtureFile(): File {
        var directory = File(System.getProperty("user.dir") ?: ".")
        repeat(5) {
            val candidate = File(directory, "protocol/fixtures/movement-v12.json")
            if (candidate.isFile) return candidate
            directory = directory.parentFile ?: return@repeat
        }
        error("could not find protocol/fixtures/movement-v12.json")
    }
}
