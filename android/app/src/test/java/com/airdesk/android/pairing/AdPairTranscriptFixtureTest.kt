package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId
import com.airdesk.android.util.Base64Url
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

class AdPairTranscriptFixtureTest {
    @Test
    fun reproducesCrossPlatformTranscriptHashSasAndSessionKeys() {
        val fixture = Json.parseToJsonElement(resourceText("/ad-pair-1.json")).jsonObject
        val offer = PairingJson.strict.decodeFromString<AdPairOffer>(fixture.getValue("offer").toString())
        val response = PairingJson.strict.decodeFromString<AdPairOffer>(fixture.getValue("response").toString())
        val pakeJson = fixture.getValue("pake").jsonObject
        val pake = AdPairPakeEvidence(
            initiatorShare = pakeJson.getValue("initiatorShare").jsonPrimitive.content,
            responderShare = pakeJson.getValue("responderShare").jsonPrimitive.content,
            initiatorConfirmation = pakeJson.getValue("initiatorConfirmation").jsonPrimitive.content,
            responderConfirmation = pakeJson.getValue("responderConfirmation").jsonPrimitive.content,
        )
        val expected = fixture.getValue("expected").jsonObject
        val transcript = AdPairTranscript.canonical(offer, response, pake)
        val hash = AdPairTranscript.hash(offer, response, pake)

        assertEquals(expected.getValue("transcript").jsonPrimitive.content, DeviceId.hexLowercase(transcript))
        assertEquals(expected.getValue("transcriptHash").jsonPrimitive.content, DeviceId.hexLowercase(hash))
        assertEquals(
            expected.getValue("shortAuthenticationString").jsonPrimitive.content,
            AdPairTranscript.shortAuthenticationString(hash),
        )

        val keys = AdPairKeySchedule.derive(
            pakeSharedSecret = Base64Url.decode(pakeJson.getValue("sharedSecret").jsonPrimitive.content),
            transcriptHash = hash,
            channelBinding = offer.channelBinding,
        )
        val expectedKeys = expected.getValue("sessionKeys").jsonObject
        assertEquals(expectedKeys.getValue("initiatorToResponder").jsonPrimitive.content, DeviceId.hexLowercase(keys.initiatorToResponder.bytes))
        assertEquals(expectedKeys.getValue("responderToInitiator").jsonPrimitive.content, DeviceId.hexLowercase(keys.responderToInitiator.bytes))
        assertEquals(expectedKeys.getValue("transport").jsonPrimitive.content, DeviceId.hexLowercase(keys.transport.bytes))
    }

    private fun resourceText(name: String): String =
        requireNotNull(javaClass.getResourceAsStream(name)) { "missing resource $name" }
            .bufferedReader()
            .use { it.readText() }
}
