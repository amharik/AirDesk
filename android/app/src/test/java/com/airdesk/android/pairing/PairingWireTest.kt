package com.airdesk.android.pairing

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class PairingWireTest {
    private val bytes = ByteArray(32) { (it + 1).toByte() }

    @Test
    fun roundTripsEveryKind() {
        val messages = listOf(
            PairingWire.response(bytes),
            PairingWire.share(bytes),
            PairingWire.verifierResponse(bytes, bytes, bytes),
            PairingWire.initiatorFinish(bytes, bytes),
            PairingWire.responderFinish(bytes, bytes),
        )
        for (message in messages) {
            assertEquals(message, PairingWire.decode(PairingWire.encode(message)))
            assertEquals(message, PairingWire.decode(PairingWire.encode(message).toString(Charsets.UTF_8)))
        }
    }

    @Test
    fun acceptsBrowserEncodedVerifierResponse() {
        val encoded = """{"protocol":"adpair-wire","version":1,"kind":"verifier-response","share":"AQID","confirmation":"BAUG","signature":"BwgJ"}"""
        val decoded = PairingWire.decode(encoded)
        assertEquals(PairingWire.Kind.VERIFIER_RESPONSE, decoded.kind)
        assertArrayEquals(byteArrayOf(1, 2, 3), decoded.share)
        assertArrayEquals(byteArrayOf(4, 5, 6), decoded.confirmation)
        assertArrayEquals(byteArrayOf(7, 8, 9), decoded.signature)
        assertEquals(encoded, PairingWire.encode(decoded).toString(Charsets.UTF_8))
    }

    @Test
    fun rejectsMalformedAndUnsupportedMessages() {
        expectCode(PairingWire.ErrorCode.MALFORMED) { PairingWire.decode("not json") }
        expectCode(PairingWire.ErrorCode.MALFORMED) { PairingWire.decode("[]") }
        expectCode(PairingWire.ErrorCode.MALFORMED) { PairingWire.decode("{}") }
        expectCode(PairingWire.ErrorCode.UNSUPPORTED_PROTOCOL) {
            PairingWire.decode("""{"protocol":"other","version":1,"kind":"response","response":"AQ"}""")
        }
        expectCode(PairingWire.ErrorCode.UNSUPPORTED_VERSION) {
            PairingWire.decode("""{"protocol":"adpair-wire","version":2,"kind":"response","response":"AQ"}""")
        }
        expectCode(PairingWire.ErrorCode.INVALID_PAYLOAD) {
            PairingWire.decode("""{"protocol":"adpair-wire","version":1,"kind":"unknown","response":"AQ"}""")
        }
    }

    @Test
    fun rejectsUnexpectedOrMissingPayloads() {
        expectCode(PairingWire.ErrorCode.INVALID_PAYLOAD) {
            PairingWire.decode("""{"protocol":"adpair-wire","version":1,"kind":"response"}""")
        }
        expectCode(PairingWire.ErrorCode.INVALID_PAYLOAD) {
            PairingWire.decode("""{"protocol":"adpair-wire","version":1,"kind":"response","response":"AQ","share":"Ag"}""")
        }
        expectCode(PairingWire.ErrorCode.INVALID_PAYLOAD) {
            PairingWire.decode("""{"protocol":"adpair-wire","version":1,"kind":"verifier-response","share":"AQ","confirmation":"Ag"}""")
        }
        expectCode(PairingWire.ErrorCode.INVALID_PAYLOAD) {
            PairingWire.decode("""{"protocol":"adpair-wire","version":1,"kind":"response","response":""}""")
        }
        expectCode(PairingWire.ErrorCode.INVALID_PAYLOAD) {
            PairingWire.decode("""{"protocol":"adpair-wire","version":1,"kind":"response","response":"%%%"}""")
        }
        expectCode(PairingWire.ErrorCode.INVALID_PAYLOAD) {
            PairingWire.response(ByteArray(0))
        }
    }

    private fun expectCode(code: PairingWire.ErrorCode, block: () -> Unit) {
        try {
            block()
            fail("expected ${code.name}")
        } catch (error: PairingWire.PairingWireException) {
            assertEquals(code, error.code)
        }
    }
}
