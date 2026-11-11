import XCTest
@testable import AirDesk

final class CapabilityLeaseInvocationTests: XCTestCase {
    private let now: Int64 = 3_000
    private let workspaceId = "workspace-1"
    private let applicationId = "com.example.editor"
    private let sessionId = "session-1"

    func testIssuedLeaseAuthorizesMatchingInvocationAndRecordsAudit() throws {
        let fixture = try makeFixture()
        var handled: CapabilityInvocation?
        let service = CapabilityInvocationService(authorizer: fixture.authorizer)
        service.handler = { invocation in
            handled = invocation
            return Data("ok".utf8)
        }

        let output = try service.invoke(
            CapabilityInvocationRequest(
                invocationId: "invocation-1",
                authorization: try fixture.request(),
                payload: Data("hello".utf8)
            )
        )

        XCTAssertEqual(output, Data("ok".utf8))
        XCTAssertEqual(handled?.leaseId, fixture.lease.leaseId)
        XCTAssertEqual(handled?.grantJti, fixture.delegatedGrant.claims.jti)
        XCTAssertEqual(handled?.payload, Data("hello".utf8))
        XCTAssertEqual(service.auditEvents.count, 1)
        XCTAssertEqual(service.auditEvents[0].decision, .allowed)
        XCTAssertEqual(service.auditEvents[0].invocationId, "invocation-1")
        XCTAssertEqual(service.auditEvents[0].auditId, fixture.lease.auditId)
        XCTAssertEqual(service.auditEvents[0].payloadBytes, 5)
    }

    func testLeaseIssuanceRejectsExpiredWidenedAndDuplicateLeases() throws {
        let fixture = try makeFixture()
        XCTAssertThrowsError(
            try fixture.leases.issue(
                grant: fixture.delegatedGrant,
                request: fixture.leaseRequest(
                    leaseId: "too-long",
                    operations: ["read"],
                    expiresAtMillis: 20_000
                )
            )
        ) { error in
            guard case .invalidLease = error as? CapabilityAccessError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertThrowsError(
            try fixture.leases.issue(
                grant: fixture.delegatedGrant,
                request: fixture.leaseRequest(
                    leaseId: "widened",
                    operations: ["write"],
                    expiresAtMillis: 5_000
                )
            )
        ) { error in
            guard case .invalidLease = error as? CapabilityAccessError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertThrowsError(
            try fixture.leases.issue(
                grant: fixture.delegatedGrant,
                request: fixture.leaseRequest(
                    leaseId: fixture.lease.leaseId,
                    operations: ["read"],
                    expiresAtMillis: 5_000
                )
            )
        ) { error in
            guard case .invalidLease = error as? CapabilityAccessError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testRevokedGrantAndLeaseAreDenied() throws {
        let fixture = try makeFixture()
        try fixture.revocations.add(
            CapabilityRevocationRecord(
                iss: fixture.policy.revocationIssuer,
                seq: 2,
                issuedAtMillis: now,
                entries: [
                    CapabilityRevocationEntry(
                        ref: fixture.delegatedGrant.claims.jti,
                        kind: .grant,
                        atMillis: now,
                        reason: "user-revoked"
                    )
                ]
            )
        )
        assertError(.revoked, try fixture.authorizer.authorize(fixture.request()))

        let leaseFixture = try makeFixture()
        try leaseFixture.revocations.add(
            CapabilityRevocationRecord(
                iss: leaseFixture.policy.revocationIssuer,
                seq: 2,
                issuedAtMillis: now,
                entries: [
                    CapabilityRevocationEntry(
                        ref: leaseFixture.lease.leaseId,
                        kind: .lease,
                        atMillis: now,
                        reason: "device-revoked"
                    )
                ]
            )
        )
        assertError(.revoked, try leaseFixture.authorizer.authorize(leaseFixture.request()))
    }

    func testStaleOrMissingRevocationDataIsRejected() throws {
        let fixture = try makeFixture()
        let strictPolicy = CapabilityAuthorizationPolicy(
            providerDeviceId: fixture.policy.providerDeviceId,
            approvedRootIssuers: fixture.policy.approvedRootIssuers,
            revocationIssuer: fixture.policy.revocationIssuer,
            maxRevocationStalenessMillis: 10
        )
        let strict = try CapabilityAuthorizer(
            policy: strictPolicy,
            leases: fixture.leases,
            revocations: fixture.revocations
        )
        assertError(.revocationStale, try strict.authorize(fixture.request()))

        let emptyStore = CapabilityRevocationStore()
        let noRecord = try CapabilityAuthorizer(
            policy: fixture.policy,
            leases: fixture.leases,
            revocations: emptyStore
        )
        assertError(.revocationStale, try noRecord.authorize(fixture.request()))
    }

    func testProofOfPossessionIsRequiredByConfirmationClaim() throws {
        let fixture = try makeFixture()
        var request = try fixture.request()
        request.possession = nil
        assertError(.missingProof, try fixture.authorizer.authorize(request))

        request = try fixture.request()
        request.possession = try CapabilityPossession.sign(
            grant: fixture.delegatedGrant,
            identity: fixture.provider
        )
        assertError(.confirmationMismatch, try fixture.authorizer.authorize(request))

        request = try fixture.request()
        request.possession?.proof.signature = Data([0x01, 0x02])
        assertError(.proofMismatch, try fixture.authorizer.authorize(request))
    }

    func testRootIssuerParentAndAttenuationAreEnforced() throws {
        let fixture = try makeFixture()
        let unapprovedPolicy = CapabilityAuthorizationPolicy(
            providerDeviceId: fixture.policy.providerDeviceId,
            approvedRootIssuers: [fixture.delegate.deviceId],
            revocationIssuer: fixture.policy.revocationIssuer,
            maxRevocationStalenessMillis: fixture.policy.maxRevocationStalenessMillis
        )
        let unapproved = try CapabilityAuthorizer(
            policy: unapprovedPolicy,
            leases: fixture.leases,
            revocations: fixture.revocations
        )
        assertError(.rootIssuerNotApproved, try unapproved.authorize(fixture.request()))

        let wrongParent = try makeDelegatedGrant(
            fixture: fixture,
            parent: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            operations: ["read"]
        )
        let lease = try fixture.leases.issue(
            grant: wrongParent,
            request: fixture.leaseRequest(
                leaseId: "wrong-parent",
                operations: ["read"],
                expiresAtMillis: 5_000
            )
        )
        var request = try fixture.request()
        request.chain = [fixture.rootGrant, wrongParent]
        request.leaseId = lease.leaseId
        request.possession = try CapabilityPossession.sign(
            grant: wrongParent,
            identity: fixture.requester
        )
        assertError(.parentMismatch, try fixture.authorizer.authorize(request))

        let widened = try makeDelegatedGrant(
            fixture: fixture,
            parent: fixture.rootGrant.tokenHashBase64URL,
            operations: ["read", "delete"]
        )
        request = try fixture.request()
        request.chain = [fixture.rootGrant, widened]
        assertError(.attenuationWidened, try fixture.authorizer.authorize(request))
    }

    func testExpiredLeaseAndMissingLeaseAreDenied() throws {
        let fixture = try makeFixture()
        var request = try fixture.request()
        request.leaseId = "missing"
        assertError(.leaseNotActive("missing"), try fixture.authorizer.authorize(request))

        request = try fixture.request()
        request.nowMillis = 6_000
        assertError(.leaseExpired, try fixture.authorizer.authorize(request))

        request = try fixture.request()
        request.nowMillis = 11_000
        assertError(.expired, try fixture.authorizer.authorize(request))
    }

    func testLeaseContextAndOperationMismatchAreDenied() throws {
        let fixture = try makeFixture()
        var request = try fixture.request()
        request.workspaceId = "other-workspace"
        assertError(
            .invalidLease("lease request context mismatch"),
            try fixture.authorizer.authorize(request)
        )

        request = try fixture.request()
        request.operation = "write"
        assertError(.operationNotGranted("write"), try fixture.authorizer.authorize(request))
    }

    func testManagerRevocationIsEnforced() throws {
        let fixture = try makeFixture()
        let service = CapabilityInvocationService(authorizer: fixture.authorizer)
        service.handler = { _ in Data() }

        XCTAssertTrue(fixture.leases.revoke(leaseId: fixture.lease.leaseId))
        XCTAssertThrowsError(
            try service.invoke(
                CapabilityInvocationRequest(
                    invocationId: "revoked",
                    authorization: try fixture.request(),
                    payload: Data()
                )
            )
        ) { error in
            XCTAssertEqual(error as? CapabilityAccessError, .leaseRevoked)
        }
        XCTAssertEqual(service.auditEvents.last?.decision, .revoked)
    }

    func testGrantTamperingAndIssuerMismatchAreRejected() throws {
        let fixture = try makeFixture()
        let claims = fixture.delegatedGrant.claims
        XCTAssertThrowsError(
            try CapabilityGrant(
                claims: claims,
                token: Data([0x00]),
                issuerKey: fixture.delegate.publicKey,
                signature: fixture.delegatedGrant.signature
            )
        ) { error in
            XCTAssertEqual(error as? CapabilityAccessError, .grantTokenMismatch)
        }
        XCTAssertThrowsError(
            try CapabilityGrant(
                claims: claims,
                token: fixture.delegatedGrant.token,
                issuerKey: fixture.delegate.publicKey,
                signature: Data([0x00])
            )
        ) { error in
            XCTAssertEqual(error as? CapabilityAccessError, .grantSignatureInvalid)
        }
        XCTAssertThrowsError(
            try CapabilityGrant(
                claims: claims,
                token: fixture.delegatedGrant.token,
                issuerKey: fixture.provider.publicKey,
                signature: fixture.delegatedGrant.signature
            )
        ) { error in
            XCTAssertEqual(error as? CapabilityAccessError, .issuerMismatch)
        }
    }

    private func makeFixture() throws -> Fixture {
        let root = try DeviceIdentity()
        let delegate = try DeviceIdentity()
        let provider = try DeviceIdentity()
        let requester = try DeviceIdentity()

        let rootClaims = CapabilityGrantClaims(
            iss: root.deviceId,
            sub: delegate.deviceId,
            aud: provider.deviceId,
            jti: "grant-root",
            capUri: "airdesk://fs/documents",
            operations: ["read", "write"],
            notBeforeMillis: 1_000,
            expiresAtMillis: 10_000,
            epochId: 7,
            cnf: nil,
            parent: nil
        )
        let rootGrant = try CapabilityGrant(claims: rootClaims, issuer: root)

        let delegatedClaims = CapabilityGrantClaims(
            iss: delegate.deviceId,
            sub: provider.deviceId,
            aud: provider.deviceId,
            jti: "grant-delegated",
            capUri: "airdesk://fs/documents/contracts",
            operations: ["read"],
            notBeforeMillis: 1_500,
            expiresAtMillis: 9_000,
            epochId: 7,
            cnf: CapabilityPossession.confirmationThumbprint(requester.publicKey),
            parent: rootGrant.tokenHashBase64URL
        )
        let delegatedGrant = try CapabilityGrant(claims: delegatedClaims, issuer: delegate)

        let policy = CapabilityAuthorizationPolicy(
            providerDeviceId: provider.deviceId,
            approvedRootIssuers: [root.deviceId],
            revocationIssuer: provider.deviceId,
            maxRevocationStalenessMillis: 5_000
        )
        let leases = CapabilityLeaseManager()
        let revocations = CapabilityRevocationStore()
        try revocations.add(
            CapabilityRevocationRecord(
                iss: provider.deviceId,
                seq: 1,
                issuedAtMillis: 2_000,
                entries: []
            )
        )
        let lease = try leases.issue(
            grant: delegatedGrant,
            request: CapabilityLeaseIssueRequest(
                leaseId: "lease-1",
                workspaceId: workspaceId,
                applicationId: applicationId,
                requesterDeviceId: requester.deviceId,
                sessionId: sessionId,
                operations: ["read"],
                issuedAtMillis: 2_000,
                expiresAtMillis: 5_000,
                auditId: "audit-1"
            )
        )
        let authorizer = try CapabilityAuthorizer(
            policy: policy,
            leases: leases,
            revocations: revocations
        )
        return Fixture(
            root: root,
            delegate: delegate,
            provider: provider,
            requester: requester,
            rootGrant: rootGrant,
            delegatedGrant: delegatedGrant,
            lease: lease,
            leases: leases,
            revocations: revocations,
            policy: policy,
            authorizer: authorizer
        )
    }

    private func makeDelegatedGrant(
        fixture: Fixture,
        parent: String,
        operations: [String]
    ) throws -> CapabilityGrant {
        try CapabilityGrant(
            claims: CapabilityGrantClaims(
                iss: fixture.delegate.deviceId,
                sub: fixture.provider.deviceId,
                aud: fixture.provider.deviceId,
                jti: "grant-delegated-\(parent.prefix(8))-\(operations.joined(separator: "-"))",
                capUri: "airdesk://fs/documents/contracts",
                operations: operations,
                notBeforeMillis: 1_500,
                expiresAtMillis: 9_000,
                epochId: 7,
                cnf: CapabilityPossession.confirmationThumbprint(
                    fixture.requester.publicKey
                ),
                parent: parent
            ),
            issuer: fixture.delegate
        )
    }

    private func assertError(
        _ expected: CapabilityAccessError,
        _ expression: @autoclosure () throws -> Any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard let error = error as? CapabilityAccessError else {
                return XCTFail("unexpected error: \(error)", file: file, line: line)
            }
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }
}

private struct Fixture {
    let root: DeviceIdentity
    let delegate: DeviceIdentity
    let provider: DeviceIdentity
    let requester: DeviceIdentity
    let rootGrant: CapabilityGrant
    let delegatedGrant: CapabilityGrant
    let lease: CapabilityGrantLease
    let leases: CapabilityLeaseManager
    let revocations: CapabilityRevocationStore
    let policy: CapabilityAuthorizationPolicy
    let authorizer: CapabilityAuthorizer

    func leaseRequest(
        leaseId: String,
        operations: [String],
        expiresAtMillis: Int64
    ) -> CapabilityLeaseIssueRequest {
        CapabilityLeaseIssueRequest(
            leaseId: leaseId,
            workspaceId: "workspace-1",
            applicationId: "com.example.editor",
            requesterDeviceId: requester.deviceId,
            sessionId: "session-1",
            operations: operations,
            issuedAtMillis: 2_000,
            expiresAtMillis: expiresAtMillis,
            auditId: "audit-\(leaseId)"
        )
    }

    func request() throws -> CapabilityAuthorizationRequest {
        var context = CapabilityAuthorizationRequest(
            chain: [rootGrant, delegatedGrant],
            leaseId: lease.leaseId,
            workspaceId: lease.workspaceId,
            applicationId: lease.applicationId,
            requesterDeviceId: lease.requesterDeviceId,
            sessionId: lease.sessionId,
            capUri: delegatedGrant.claims.capUri,
            operation: "read",
            epochId: 7,
            nowMillis: 3_000,
            possession: nil
        )
        context.possession = try CapabilityPossession.sign(
            grant: delegatedGrant,
            identity: requester
        )
        return context
    }
}
