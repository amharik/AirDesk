import XCTest
@testable import AirDesk

final class DeviceAgentTests: XCTestCase {
    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("protocol/fixtures/device-agent/contract-v1.json")

    private var fixture: [String: Any]!

    override func setUpWithError() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testFixtureIdentityCapabilitiesAndHealth() throws {
        let agent = try makeAgent()
        XCTAssertEqual(agent.state, .starting)

        let identity = agent.identity()
        let identityFixture = try dictionary(fixture["identity"])
        XCTAssertEqual(identity.deviceId, try string(identityFixture["deviceId"]))
        XCTAssertEqual(identity.displayName, try string(identityFixture["displayName"]))
        XCTAssertEqual(identity.platform, try string(identityFixture["platform"]))
        XCTAssertEqual(identity.algorithm, try string(identityFixture["algorithm"]))
        XCTAssertEqual(
            identity.publicKeySpkiBase64Url,
            try string(identityFixture["publicKeySpkiBase64Url"])
        )
        XCTAssertEqual(
            identity.createdAtEpochMillis,
            try int64(identityFixture["createdAtEpochMillis"])
        )

        let capabilities = agent.capabilities()
        XCTAssertEqual(capabilities.count, try array(fixture["capabilities"]).count)
        XCTAssertEqual(capabilities.map(\.capUri), capabilities.map(\.capUri).sorted())
        XCTAssertEqual(Set(capabilities.map(\.capUri)).count, capabilities.count)

        let documents = try XCTUnwrap(capabilities.first {
            $0.capUri == "airdesk://fs/documents/read"
        })
        XCTAssertEqual(documents.availability, .available)
        XCTAssertEqual(documents.authorization, .ungranted)

        let display = try XCTUnwrap(capabilities.first {
            $0.capUri == "airdesk://display/output"
        })
        XCTAssertEqual(display.availability, .unavailable)
        XCTAssertEqual(display.authorization, .granted)

        let healthFixture = try dictionary(fixture["health"])
        XCTAssertEqual(agent.health().state, .starting)
        XCTAssertEqual(agent.health().generation, 0)
        XCTAssertEqual(agent.health().capabilityCount, capabilities.count)

        agent.start()
        let health = agent.health()
        XCTAssertEqual(health.state, try lifecycleState(string(healthFixture["state"])))
        XCTAssertEqual(health.generation, try uint64(healthFixture["generation"]))
        XCTAssertEqual(health.uptimeMillis, try int64(healthFixture["uptimeMillis"]))
        XCTAssertEqual(
            health.availableCapabilityCount,
            try int(healthFixture["availableCapabilityCount"])
        )
        XCTAssertEqual(
            health.busyCapabilityCount,
            try int(healthFixture["busyCapabilityCount"])
        )
        XCTAssertEqual(
            health.restrictedCapabilityCount,
            try int(healthFixture["restrictedCapabilityCount"])
        )
        XCTAssertEqual(
            health.unavailableCapabilityCount,
            try int(healthFixture["unavailableCapabilityCount"])
        )
        XCTAssertEqual(
            health.authorizedCapabilityCount,
            try int(healthFixture["authorizedCapabilityCount"])
        )
        XCTAssertEqual(health.activeLeaseCount, 0)
    }

    func testFixtureRequestCases() throws {
        for item in try array(fixture["requestCases"]) {
            let name = try string(item["name"])
            let agent = try makeAgent()
            agent.start()
            let request = try makeRequest(from: try dictionary(item["request"]))
            let expected = try dictionary(item["expected"])

            if try bool(expected["ok"]) {
                let lease = try agent.requestCapability(request)
                XCTAssertEqual(lease.leaseId, try string(expected["leaseId"]), name)
                XCTAssertEqual(lease.auditId, try string(expected["auditId"]), name)
                XCTAssertEqual(lease.capUri, try string(expected["capUri"]), name)
                XCTAssertEqual(
                    lease.operations,
                    try stringArray(expected["operations"]),
                    name
                )
                XCTAssertEqual(
                    lease.workspaceId,
                    try string(expected["workspaceId"]),
                    name
                )
                XCTAssertEqual(
                    lease.applicationId,
                    try string(expected["applicationId"]),
                    name
                )
                XCTAssertEqual(
                    lease.requesterDeviceId,
                    try string(expected["requesterDeviceId"]),
                    name
                )
                XCTAssertEqual(lease.sessionId, try string(expected["sessionId"]), name)
                XCTAssertEqual(
                    lease.issuedAtEpochMillis,
                    try int64(expected["issuedAtEpochMillis"]),
                    name
                )
                XCTAssertEqual(
                    lease.expiresAtEpochMillis,
                    try int64(expected["expiresAtEpochMillis"]),
                    name
                )
                XCTAssertEqual(agent.activeLeases(), [lease], name)
            } else {
                let expectedCode = try string(expected["code"])
                do {
                    _ = try agent.requestCapability(request)
                    XCTFail("\(name): expected \(expectedCode)")
                } catch {
                    let typedError = try XCTUnwrap(error as? DeviceAgentError, name)
                    XCTAssertEqual(typedError.code, expectedCode, name)
                    if let permission = expected["permission"] as? String {
                        XCTAssertEqual(typedError, .platformPermissionDenied(permission), name)
                    }
                    if let operation = expected["operation"] as? String {
                        XCTAssertEqual(typedError, .operationNotAllowed(operation), name)
                    }
                }
                XCTAssertTrue(agent.activeLeases().isEmpty, name)
            }
        }
    }

    func testFixtureReleaseCases() throws {
        let agent = try makeAgent()
        agent.start()
        _ = try agent.requestCapability(try request(named: "camera-authorized"))

        for item in try array(fixture["releaseCases"]) {
            let name = try string(item["name"])
            let leaseId = try string(item["leaseId"])
            let expected = try dictionary(item["expected"])
            if try bool(expected["ok"]) {
                try agent.releaseCapability(leaseId: leaseId)
                XCTAssertTrue(agent.activeLeases().isEmpty, name)
            } else {
                do {
                    try agent.releaseCapability(leaseId: leaseId)
                    XCTFail("\(name): expected \(try string(expected["code"]))")
                } catch {
                    XCTAssertEqual(
                        (error as? DeviceAgentError)?.code,
                        try string(expected["code"]),
                        name
                    )
                }
            }
        }
    }

    func testFixtureSubscriptionsAndTypedLifecycle() throws {
        let subscriptions = try dictionary(fixture["subscriptions"])
        let agent = try makeAgent()
        for eventType in try stringArray(subscriptions["eventTypes"]) {
            let subscription = try agent.subscribe(eventType: eventType) { _ in }
            XCTAssertTrue(subscription.isActive)
            subscription.cancel()
            XCTAssertFalse(subscription.isActive)
        }
        XCTAssertThrowsError(try agent.subscribe(
            eventType: try string(subscriptions["invalidEventType"])
        ) { _ in }) { error in
            XCTAssertEqual(
                (error as? DeviceAgentError)?.code,
                "invalid-event-type"
            )
        }

        var leaseEvents: [DeviceAgentEvent] = []
        var lifecycleEvents: [DeviceAgentEvent] = []
        let leaseSubscription = try agent.subscribe(eventType: "lease") {
            leaseEvents.append($0)
        }
        let lifecycleSubscription = try agent.subscribe(eventType: "lifecycle") {
            lifecycleEvents.append($0)
        }
        defer {
            leaseSubscription.cancel()
            lifecycleSubscription.cancel()
        }

        agent.start()
        let cameraRequest = try request(named: "camera-authorized")
        _ = try agent.requestCapability(cameraRequest)
        XCTAssertEqual(leaseEvents.last?.type, .lease)
        XCTAssertEqual(leaseEvents.last?.action, "granted")
        XCTAssertEqual(leaseEvents.last?.leaseId, "lease-camera-1")

        try agent.releaseCapability(leaseId: "lease-camera-1")
        XCTAssertEqual(leaseEvents.last?.action, "released")
        XCTAssertEqual(leaseEvents.last?.leaseId, "lease-camera-1")

        _ = try agent.requestCapability(cameraRequest)
        agent.disconnect()
        XCTAssertEqual(agent.state, .unavailable)
        XCTAssertTrue(agent.activeLeases().isEmpty)
        XCTAssertEqual(leaseEvents.last?.action, "revoked")
        XCTAssertEqual(lifecycleEvents.last?.state, .unavailable)

        do {
            _ = try agent.requestCapability(cameraRequest)
            XCTFail("expected unavailable agent to reject requests")
        } catch {
            let typedError = try XCTUnwrap(error as? DeviceAgentError)
            XCTAssertEqual(typedError, .agentUnavailable)
        }
    }

    private func makeAgent() throws -> DeviceAgent {
        let identityFixture = try dictionary(fixture["identity"])
        let identity = DeviceAgentIdentity(
            deviceId: try string(identityFixture["deviceId"]),
            displayName: try string(identityFixture["displayName"]),
            platform: try string(identityFixture["platform"]),
            algorithm: try string(identityFixture["algorithm"]),
            publicKeySpkiBase64Url: try string(identityFixture["publicKeySpkiBase64Url"]),
            createdAtEpochMillis: try int64(identityFixture["createdAtEpochMillis"])
        )
        let capabilities = try array(fixture["capabilities"]).map(makeCapability)
        var permissions: [String: DeviceAgentPlatformPermissionState] = [:]
        for (permission, state) in try dictionary(fixture["platformPermissions"]) {
            permissions[permission] = try XCTUnwrap(
                DeviceAgentPlatformPermissionState(rawValue: try string(state))
            )
        }
        let now = try int64(fixture["nowEpochMillis"])
        return try DeviceAgent(
            identity: identity,
            capabilities: capabilities,
            permissions: permissions,
            leaseDurationMillis: try int64(fixture["leaseDurationMillis"]),
            now: { now }
        )
    }

    private func makeCapability(_ item: [String: Any]) throws -> DeviceAgentCapability {
        let availability: [String: CapabilityAvailability] = [
            "available": .available,
            "busy": .busy,
            "restricted": .restricted,
            "unavailable": .unavailable
        ]
        let authorization: [String: CapabilityAuthorization] = [
            "ungranted": .ungranted,
            "granted": .granted,
            "denied": .denied,
            "revoked": .revoked
        ]
        return DeviceAgentCapability(
            capUri: try string(item["capUri"]),
            version: UInt32(try int(item["version"])),
            providerDeviceId: try string(item["providerDeviceId"]),
            operations: try stringArray(item["operations"]),
            permissions: try stringArray(item["permissions"]),
            execution: try string(item["execution"]),
            transport: try string(item["transport"]),
            constraints: try string(item["constraints"]),
            availability: try XCTUnwrap(availability[try string(item["availability"])]),
            authorization: try XCTUnwrap(authorization[try string(item["authorization"])]),
            label: try string(item["label"]),
            summary: try string(item["summary"]),
            note: try string(item["note"]),
            authorizationRef: item["authorizationRef"] as? String
        )
    }

    private func makeRequest(
        from item: [String: Any]
    ) throws -> DeviceAgentCapabilityRequest {
        DeviceAgentCapabilityRequest(
            capUri: try string(item["capUri"]),
            operations: try stringArray(item["operations"]),
            workspaceId: try string(item["workspaceId"]),
            applicationId: try string(item["applicationId"]),
            requesterDeviceId: try string(item["requesterDeviceId"]),
            sessionId: try string(item["sessionId"]),
            leaseId: item["leaseId"] as? String,
            auditId: item["auditId"] as? String
        )
    }

    private func request(named name: String) throws -> DeviceAgentCapabilityRequest {
        let item = try XCTUnwrap(try array(fixture["requestCases"]).first {
            ($0["name"] as? String) == name
        })
        return try makeRequest(from: try dictionary(item["request"]))
    }

    private func lifecycleState(_ value: String) throws -> DeviceAgentLifecycleState {
        try XCTUnwrap(DeviceAgentLifecycleState(rawValue: value))
    }

    private func dictionary(_ value: Any?) throws -> [String: Any] {
        try XCTUnwrap(value as? [String: Any])
    }

    private func array(_ value: Any?) throws -> [[String: Any]] {
        try XCTUnwrap(value as? [[String: Any]])
    }

    private func string(_ value: Any?) throws -> String {
        try XCTUnwrap(value as? String)
    }

    private func stringArray(_ value: Any?) throws -> [String] {
        try XCTUnwrap(value as? [String])
    }

    private func int(_ value: Any?) throws -> Int {
        try XCTUnwrap(value as? Int)
    }

    private func int64(_ value: Any?) throws -> Int64 {
        Int64(try XCTUnwrap(value as? NSNumber).int64Value)
    }

    private func uint64(_ value: Any?) throws -> UInt64 {
        UInt64(try XCTUnwrap(value as? NSNumber).uint64Value)
    }

    private func bool(_ value: Any?) throws -> Bool {
        try XCTUnwrap(value as? Bool)
    }
}
