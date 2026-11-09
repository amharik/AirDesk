package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId
import com.airdesk.android.util.Base64Url
import java.security.KeyPairGenerator
import java.security.spec.ECGenParameterSpec
import com.airdesk.android.pairing.AdPairWireSession.Role
import com.airdesk.android.pairing.AdPairWireSession.State
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class AdPairSocketTransportTest {
    @Test
    fun drivesWireSessionOverSocketConnector() {
        val hub = LoopbackHub()
        val hostSession = session(Role.HOST)
        hostSession.startHost(
            mode = "pin",
            channelBinding = binding(),
            endpointHint = "wss://relay.example/room",
        )
        val controller = session(Role.CONTROLLER)
        val joinMessage = controller.join(hostSession.code!!, pin = hostSession.pin)
        val hostTransport = AdPairSocketTransport(hostSession, hub)
        val controllerTransport = AdPairSocketTransport(controller, hub)
        hub.nextName = "host"
        hostTransport.connect("wss://relay.example/room")
        hub.nextName = "controller"
        controllerTransport.connect("wss://relay.example/room", joinMessage)
        hub.openAll()

        assertEquals(State.AWAITING_USER_VERIFICATION, hostSession.state)
        assertEquals(State.AWAITING_USER_VERIFICATION, controller.state)
        assertNotNull(hostSession.shortAuthenticationString)
        assertEquals(hostSession.shortAuthenticationString, controller.shortAuthenticationString)
        assertNull(hostTransport.lastError)

        val hostKeys = hostTransport.confirmShortAuthenticationString(hostSession.shortAuthenticationString!!)
        val controllerKeys = controllerTransport.confirmShortAuthenticationString(controller.shortAuthenticationString!!)
        assertEquals(DeviceId.hexLowercase(hostKeys.transport.bytes), DeviceId.hexLowercase(controllerKeys.transport.bytes))
        controllerTransport.close()
        hostTransport.close()
    }

    private fun session(role: Role): AdPairWireSession {
        val keyPair = KeyPairGenerator.getInstance("EC").apply {
            initialize(ECGenParameterSpec("secp256r1"))
        }.generateKeyPair()
        val coordinator = AdPairCoordinator(
            role = if (role == Role.HOST) AdPairCoordinator.Role.INITIATOR else AdPairCoordinator.Role.RESPONDER,
            deviceId = DeviceId.fromSpki(keyPair.public.encoded),
            // generated key material
            publicKey = Base64Url.encode(keyPair.public.encoded),
            signer = AdPairSigner { it.copyOf() },
            verifier = AdPairSignatureVerifier { _, _, _ -> true },
        )
        return AdPairWireSession(role, coordinator)
    }

    private fun binding() = AdPairChannelBinding(
        kind = "certificate-hash",
        value = "ab".repeat(32),
    )

    private class LoopbackHub : PairingSocketConnector {
        var nextName: String = ""
        private val listeners = mutableMapOf<String, PairingSocketListener>()
        private val opens = ArrayDeque<PairingSocketListener>()

        override fun connect(url: String, listener: PairingSocketListener): PairingSocketConnection {
            listeners[nextName] = listener
            opens.addLast(listener)
            return LoopbackConnection(nextName, this)
        }

        fun openAll() {
            while (opens.isNotEmpty()) opens.removeFirst().onOpen()
        }

        fun route(from: String, data: ByteArray) {
            val target = if (from == "host") "controller" else "host"
            listeners[target]?.onBinary(data)
        }
    }

    private class LoopbackConnection(
        private val name: String,
        private val hub: LoopbackHub,
    ) : PairingSocketConnection {
        override fun send(data: ByteArray) = hub.route(name, data)
        override fun close() = Unit
    }
}
