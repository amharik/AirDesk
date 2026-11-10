package com.airdesk.android.agent

import com.airdesk.android.capabilities.Authorization
import com.airdesk.android.capabilities.Availability
import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceAgentTest {
    private val fixture: JsonObject by lazy {
        Json.parseToJsonElement(fixtureFile().readText()).jsonObject
    }

    @Test
    fun fixtureIdentityCapabilitiesAndHealth() {
        val agent = makeAgent()
        assertEquals(DeviceAgentLifecycleState.STARTING, agent.state)
        assertEquals(expectedIdentity(), agent.identity())

        val capabilities = agent.capabilities()
        assertEquals(fixture.array("capabilities").size, capabilities.size)
        assertEquals(capabilities.map { it.capUri }.sorted(), capabilities.map { it.capUri })
        assertEquals(capabilities.size, capabilities.map { it.capUri }.toSet().size)

        val documents = capabilities.first { it.capUri == "airdesk://fs/documents/read" }
        assertEquals(Availability.AVAILABLE, documents.availability)
        assertEquals(Authorization.UNGRANTED, documents.authorization)

        val display = capabilities.first { it.capUri == "airdesk://display/output" }
        assertEquals(Availability.UNAVAILABLE, display.availability)
        assertEquals(Authorization.GRANTED, display.authorization)

        assertEquals(DeviceAgentLifecycleState.STARTING, agent.health().state)
        assertEquals(0L, agent.health().generation)
        assertEquals(capabilities.size, agent.health().capabilityCount)

        agent.start()
        assertEquals(expectedHealth(), agent.health())
    }

    @Test
    fun fixtureRequestCases() {
        fixture.array("requestCases").forEach { element ->
            val item = element.jsonObject
            val name = item.string("name")
            val agent = makeAgent()
            agent.start()
            val request = makeRequest(item.obj("request"))
            val expected = item.obj("expected")

            if (expected.bool("ok")) {
                val lease = agent.requestCapability(request)
                assertEquals(name, expected.string("leaseId"), lease.leaseId)
                assertEquals(name, expected.string("auditId"), lease.auditId)
                assertEquals(name, expected.string("capUri"), lease.capUri)
                assertEquals(name, expected.stringList("operations"), lease.operations)
                assertEquals(name, expected.string("workspaceId"), lease.workspaceId)
                assertEquals(name, expected.string("applicationId"), lease.applicationId)
                assertEquals(
                    name,
                    expected.string("requesterDeviceId"),
                    lease.requesterDeviceId,
                )
                assertEquals(name, expected.string("sessionId"), lease.sessionId)
                assertEquals(
                    name,
                    expected.long("issuedAtEpochMillis"),
                    lease.issuedAtEpochMillis,
                )
                assertEquals(
                    name,
                    expected.long("expiresAtEpochMillis"),
                    lease.expiresAtEpochMillis,
                )
                assertEquals(name, listOf(lease), agent.activeLeases())
            } else {
                val error = assertThrows(DeviceAgentException::class.java) {
                    agent.requestCapability(request)
                }
                assertEquals(name, expected.string("code"), error.code.wire)
                expected.optionalString("permission")?.let {
                    assertEquals(name, it, error.detail)
                }
                expected.optionalString("operation")?.let {
                    assertEquals(name, it, error.detail)
                }
                assertTrue(name, agent.activeLeases().isEmpty())
            }
        }
    }

    @Test
    fun fixtureReleaseCases() {
        val agent = makeAgent()
        agent.start()
        agent.requestCapability(requestNamed("camera-authorized"))

        fixture.array("releaseCases").forEach { element ->
            val item = element.jsonObject
            val name = item.string("name")
            val leaseId = item.string("leaseId")
            val expected = item.obj("expected")
            if (expected.bool("ok")) {
                agent.releaseCapability(leaseId)
                assertTrue(name, agent.activeLeases().isEmpty())
            } else {
                val error = assertThrows(DeviceAgentException::class.java) {
                    agent.releaseCapability(leaseId)
                }
                assertEquals(name, expected.string("code"), error.code.wire)
            }
        }
    }

    @Test
    fun fixtureSubscriptionsAndTypedLifecycle() {
        val subscriptions = fixture.obj("subscriptions")
        val agent = makeAgent()
        subscriptions.stringList("eventTypes").forEach { eventType ->
            val subscription = agent.subscribe(eventType) {}
            assertTrue(subscription.active)
            subscription.cancel()
            assertFalse(subscription.active)
        }
        val invalid = assertThrows(DeviceAgentException::class.java) {
            agent.subscribe(subscriptions.string("invalidEventType")) {}
        }
        assertEquals(DeviceAgentErrorCode.INVALID_EVENT_TYPE, invalid.code)

        val leaseEvents = mutableListOf<DeviceAgentEvent>()
        val lifecycleEvents = mutableListOf<DeviceAgentEvent>()
        val leaseSubscription = agent.subscribe("lease") { leaseEvents.add(it) }
        val lifecycleSubscription = agent.subscribe("lifecycle") {
            lifecycleEvents.add(it)
        }

        agent.start()
        val cameraRequest = requestNamed("camera-authorized")
        agent.requestCapability(cameraRequest)
        assertEquals(DeviceAgentEventType.LEASE, leaseEvents.last().type)
        assertEquals("granted", leaseEvents.last().action)
        assertEquals("lease-camera-1", leaseEvents.last().leaseId)

        agent.releaseCapability("lease-camera-1")
        assertEquals("released", leaseEvents.last().action)
        assertEquals("lease-camera-1", leaseEvents.last().leaseId)

        agent.requestCapability(cameraRequest)
        agent.disconnect()
        assertEquals(DeviceAgentLifecycleState.UNAVAILABLE, agent.state)
        assertTrue(agent.activeLeases().isEmpty())
        assertEquals("revoked", leaseEvents.last().action)
        assertEquals(DeviceAgentLifecycleState.UNAVAILABLE, lifecycleEvents.last().state)

        val unavailable = assertThrows(DeviceAgentException::class.java) {
            agent.requestCapability(cameraRequest)
        }
        assertEquals(DeviceAgentErrorCode.AGENT_UNAVAILABLE, unavailable.code)

        leaseSubscription.cancel()
        lifecycleSubscription.cancel()
    }

    private fun makeAgent(): DeviceAgent {
        val permissions = fixture.obj("platformPermissions").mapValues { (_, value) ->
            permissionState(value.jsonPrimitive.content)
        }
        return DeviceAgent(
            identity = expectedIdentity(),
            capabilities = fixture.array("capabilities").map {
                makeCapability(it.jsonObject)
            },
            permissions = permissions,
            leaseDurationMillis = fixture.long("leaseDurationMillis"),
            now = { fixture.long("nowEpochMillis") },
        )
    }

    private fun expectedIdentity(): DeviceAgentIdentity {
        val identity = fixture.obj("identity")
        return DeviceAgentIdentity(
            deviceId = identity.string("deviceId"),
            displayName = identity.string("displayName"),
            platform = identity.string("platform"),
            algorithm = identity.string("algorithm"),
            publicKeySpkiBase64Url = identity.string("publicKeySpkiBase64Url"),
            createdAtEpochMillis = identity.long("createdAtEpochMillis"),
        )
    }

    private fun expectedHealth(): DeviceAgentHealth {
        val health = fixture.obj("health")
        return DeviceAgentHealth(
            state = lifecycleState(health.string("state")),
            generation = health.long("generation"),
            uptimeMillis = health.long("uptimeMillis"),
            capabilityCount = health.int("capabilityCount"),
            availableCapabilityCount = health.int("availableCapabilityCount"),
            busyCapabilityCount = health.int("busyCapabilityCount"),
            restrictedCapabilityCount = health.int("restrictedCapabilityCount"),
            unavailableCapabilityCount = health.int("unavailableCapabilityCount"),
            authorizedCapabilityCount = health.int("authorizedCapabilityCount"),
            activeLeaseCount = health.int("activeLeaseCount"),
        )
    }

    private fun makeCapability(item: JsonObject): DeviceAgentCapability = DeviceAgentCapability(
        capUri = item.string("capUri"),
        version = item.int("version"),
        providerDeviceId = item.string("providerDeviceId"),
        operations = item.stringList("operations"),
        permissions = item.stringList("permissions"),
        execution = item.string("execution"),
        transport = item.string("transport"),
        constraints = item.string("constraints"),
        availability = availability(item.string("availability")),
        authorization = authorization(item.string("authorization")),
        label = item.string("label"),
        summary = item.string("summary"),
        note = item.string("note"),
        authorizationRef = item.optionalString("authorizationRef"),
    )

    private fun makeRequest(item: JsonObject): DeviceAgentCapabilityRequest =
        DeviceAgentCapabilityRequest(
            capUri = item.string("capUri"),
            operations = item.stringList("operations"),
            workspaceId = item.string("workspaceId"),
            applicationId = item.string("applicationId"),
            requesterDeviceId = item.string("requesterDeviceId"),
            sessionId = item.string("sessionId"),
            leaseId = item.optionalString("leaseId"),
            auditId = item.optionalString("auditId"),
        )

    private fun requestNamed(name: String): DeviceAgentCapabilityRequest {
        val item = fixture.array("requestCases")
            .map { it.jsonObject }
            .first { it.string("name") == name }
        return makeRequest(item.obj("request"))
    }

    private fun availability(value: String): Availability = when (value) {
        "available" -> Availability.AVAILABLE
        "busy" -> Availability.BUSY
        "restricted" -> Availability.RESTRICTED
        "unavailable" -> Availability.UNAVAILABLE
        else -> error("invalid availability $value")
    }

    private fun authorization(value: String): Authorization = when (value) {
        "ungranted" -> Authorization.UNGRANTED
        "granted" -> Authorization.GRANTED
        "denied" -> Authorization.DENIED
        "revoked" -> Authorization.REVOKED
        else -> error("invalid authorization $value")
    }

    private fun lifecycleState(value: String): DeviceAgentLifecycleState =
        DeviceAgentLifecycleState.entries.first { it.wire == value }

    private fun permissionState(value: String): DeviceAgentPlatformPermissionState =
        DeviceAgentPlatformPermissionState.entries.first { it.wire == value }

    private fun fixtureFile(): File {
        var directory = File(System.getProperty("user.dir") ?: ".")
        repeat(6) {
            val candidate = File(
                directory,
                "protocol/fixtures/device-agent/contract-v1.json",
            )
            if (candidate.isFile) return candidate
            directory = directory.parentFile ?: return@repeat
        }
        error(
            "could not find protocol/fixtures/device-agent/contract-v1.json " +
                "from ${System.getProperty("user.dir")}",
        )
    }

    private fun JsonObject.obj(name: String): JsonObject =
        getValue(name).jsonObject

    private fun JsonObject.array(name: String): JsonArray =
        getValue(name).jsonArray

    private fun JsonObject.string(name: String): String =
        getValue(name).jsonPrimitive.content

    private fun JsonObject.int(name: String): Int =
        getValue(name).jsonPrimitive.int

    private fun JsonObject.long(name: String): Long =
        getValue(name).jsonPrimitive.long

    private fun JsonObject.bool(name: String): Boolean =
        getValue(name).jsonPrimitive.boolean

    private fun JsonObject.stringList(name: String): List<String> =
        array(name).map { it.jsonPrimitive.content }

    private fun JsonObject.optionalString(name: String): String? {
        val value = this[name] as? JsonPrimitive ?: return null
        return if (value.isString) value.content else null
    }
}
