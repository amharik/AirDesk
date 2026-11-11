import Foundation

enum CapabilityInvocationDecision: String, Equatable {
    case allowed
    case denied
    case expired
    case revoked
}

struct CapabilityInvocation: Equatable {
    var invocationId: String
    var capUri: String
    var operation: String
    var grantJti: String
    var leaseId: String
    var workspaceId: String
    var applicationId: String
    var requesterDeviceId: String
    var sessionId: String
    var auditId: String
    var payload: Data
}

struct CapabilityInvocationRequest: Equatable {
    var invocationId: String
    var authorization: CapabilityAuthorizationRequest
    var payload: Data
}

struct CapabilityInvocationAuditEvent: Equatable {
    var invocationId: String
    var atMillis: Int64
    var decision: CapabilityInvocationDecision
    var reason: String
    var capUri: String
    var operation: String
    var grantJti: String
    var leaseId: String
    var workspaceId: String
    var applicationId: String
    var requesterDeviceId: String
    var sessionId: String
    var auditId: String
    var payloadBytes: Int
}

final class CapabilityInvocationService {
    typealias Handler = (CapabilityInvocation) throws -> Data

    private let authorizer: CapabilityAuthorizer
    private let maxAuditEvents: Int
    private(set) var auditEvents: [CapabilityInvocationAuditEvent] = []
    var handler: Handler?
    var onAudit: ((CapabilityInvocationAuditEvent) -> Void)?

    init(authorizer: CapabilityAuthorizer, maxAuditEvents: Int = 256) {
        self.authorizer = authorizer
        self.maxAuditEvents = max(1, maxAuditEvents)
    }

    func invoke(_ request: CapabilityInvocationRequest) throws -> Data {
        let context = request.authorization
        do {
            let result = try authorizer.authorize(context)
            guard let handler else {
                throw CapabilityAccessError.handlerUnavailable
            }
            let invocation = CapabilityInvocation(
                invocationId: request.invocationId,
                capUri: result.grant.claims.capUri,
                operation: context.operation,
                grantJti: result.grant.claims.jti,
                leaseId: result.lease.leaseId,
                workspaceId: result.lease.workspaceId,
                applicationId: result.lease.applicationId,
                requesterDeviceId: result.lease.requesterDeviceId,
                sessionId: result.lease.sessionId,
                auditId: result.lease.auditId,
                payload: request.payload
            )
            let output: Data
            do {
                output = try handler(invocation)
            } catch {
                record(
                    decision: .denied,
                    reason: "invocation-handler-failed",
                    request: request,
                    result: result
                )
                throw error
            }
            record(
                decision: .allowed,
                reason: "authorized",
                request: request,
                result: result
            )
            return output
        } catch {
            record(
                decision: decision(for: error),
                reason: (error as? LocalizedError)?.errorDescription ?? String(describing: error),
                request: request,
                result: nil
            )
            throw error
        }
    }

    private func decision(for error: Error) -> CapabilityInvocationDecision {
        guard let error = error as? CapabilityAccessError else { return .denied }
        switch error {
        case .expired, .leaseExpired, .notYetValid:
            return .expired
        case .revoked, .leaseRevoked:
            return .revoked
        default:
            return .denied
        }
    }

    private func record(
        decision: CapabilityInvocationDecision,
        reason: String,
        request: CapabilityInvocationRequest,
        result: CapabilityAuthorizationResult?
    ) {
        let context = request.authorization
        let event = CapabilityInvocationAuditEvent(
            invocationId: request.invocationId,
            atMillis: context.nowMillis,
            decision: decision,
            reason: reason,
            capUri: result?.grant.claims.capUri ?? context.capUri,
            operation: context.operation,
            grantJti: result?.grant.claims.jti ?? context.chain.last?.claims.jti ?? "",
            leaseId: result?.lease.leaseId ?? context.leaseId,
            workspaceId: result?.lease.workspaceId ?? context.workspaceId,
            applicationId: result?.lease.applicationId ?? context.applicationId,
            requesterDeviceId: result?.lease.requesterDeviceId ?? context.requesterDeviceId,
            sessionId: result?.lease.sessionId ?? context.sessionId,
            auditId: result?.lease.auditId ?? "",
            payloadBytes: request.payload.count
        )
        auditEvents.append(event)
        if auditEvents.count > maxAuditEvents {
            auditEvents.removeFirst(auditEvents.count - maxAuditEvents)
        }
        onAudit?(event)
    }
}
