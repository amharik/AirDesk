import Foundation

final class RuntimeRegistry {
    private struct Candidate {
        var provider: any RuntimeProvider
        var world: RuntimeWorld
        var deviceId: String?
        var locationPriority: Int
        var preferred: Bool
    }

    private var providersByID: [String: any RuntimeProvider] = [:]
    private let hostDeviceId: String?
    private let lock = NSLock()

    init(hostDeviceId: String? = nil) {
        self.hostDeviceId = hostDeviceId
    }

    var descriptors: [RuntimeProviderDescriptor] {
        lock.lock()
        defer { lock.unlock() }
        return providersByID.values.map(\.descriptor).sorted { $0.id < $1.id }
    }

    func register(_ provider: any RuntimeProvider) throws {
        lock.lock()
        defer { lock.unlock() }
        guard providersByID[provider.descriptor.id] == nil else {
            throw RuntimeProviderError.duplicateProvider(provider.descriptor.id)
        }
        providersByID[provider.descriptor.id] = provider
    }

    func unregister(providerId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard providersByID.removeValue(forKey: providerId) != nil else {
            throw RuntimeProviderError.unknownProvider(providerId)
        }
    }

    func provider(id: String) throws -> any RuntimeProvider {
        lock.lock()
        defer { lock.unlock() }
        guard let provider = providersByID[id] else {
            throw RuntimeProviderError.unknownProvider(id)
        }
        return provider
    }

    func select(
        application: WorkspaceApplication,
        binding: WorkspaceExecutionBinding? = nil,
        placement: WorkspacePlacement? = nil,
        threading: RuntimeThreadingProfile = .singleThreaded
    ) throws -> RuntimeProviderSelection {
        lock.lock()
        let providers = providersByID.values.sorted { $0.descriptor.id < $1.descriptor.id }
        lock.unlock()

        let pinnedWorld: RuntimeWorld?
        if let pinned = binding?.pinnedWorld {
            guard let parsed = RuntimeWorld(rawValue: pinned) else {
                throw RuntimeProviderError.unknownWorld(
                    providerId: binding?.preferredProviderId ?? "unknown",
                    world: pinned
                )
            }
            pinnedWorld = parsed
        } else {
            pinnedWorld = nil
        }

        var candidates: [Candidate] = []
        var diagnostics: [RuntimePlacementDiagnostic] = []
        var firstError: RuntimeProviderError?
        var deviceMismatch: RuntimeProviderError?

        for provider in providers {
            let descriptor = provider.descriptor
            let effectiveDeviceId = descriptor.deviceId ?? hostDeviceId
            let targets = application.runtimeTargets.filter { $0.provider == descriptor.id }
            guard !targets.isEmpty else { continue }

            func record(
                _ outcome: RuntimePlacementOutcome,
                world: String? = nil,
                reason: String
            ) {
                diagnostics.append(RuntimePlacementDiagnostic(
                    providerId: descriptor.id,
                    deviceId: effectiveDeviceId,
                    world: world,
                    location: descriptor.location,
                    outcome: outcome,
                    reason: reason
                ))
            }

            func fail(_ error: RuntimeProviderError) {
                if firstError == nil {
                    firstError = error
                }
            }

            if let requestedDeviceId = placement?.deviceId,
               effectiveDeviceId != requestedDeviceId {
                record(
                    .deviceMismatch,
                    reason: "provider device \(effectiveDeviceId ?? "(unknown)") is not \(requestedDeviceId)"
                )
                if deviceMismatch == nil {
                    deviceMismatch = .deviceMismatch(deviceId: requestedDeviceId)
                }
                continue
            }
            if let providerId = placement?.providerId, providerId != descriptor.id {
                record(.placementMismatch, reason: "provider \(descriptor.id) is not the requested provider \(providerId)")
                continue
            }
            guard descriptor.availability == .available else {
                record(.unavailable, reason: "availability is \(descriptor.availability.rawValue)")
                if binding?.preferredProviderId == descriptor.id || placement?.providerId == descriptor.id {
                    fail(.providerUnavailable(descriptor.id))
                }
                continue
            }
            guard descriptor.health != .open else {
                record(.unavailable, reason: "circuit breaker is open")
                if binding?.preferredProviderId == descriptor.id || placement?.providerId == descriptor.id {
                    fail(.providerUnavailable(descriptor.id))
                }
                continue
            }
            if let preferred = binding?.preferredProviderId, !preferred.isEmpty {
                if binding?.fallbackPolicy == .deny, preferred != descriptor.id {
                    record(.placementMismatch, reason: "fallback policy deny excludes \(descriptor.id)")
                    continue
                }
                if binding?.fallbackPolicy == .localOnly && descriptor.location == .remote {
                    record(.placementMismatch, reason: "fallback policy local-only excludes remote provider \(descriptor.id)")
                    continue
                }
            }

            for target in targets {
                guard let world = RuntimeWorld(rawValue: target.world) else {
                    record(
                        .unsupportedWorld,
                        world: target.world,
                        reason: "unknown world \(target.world)"
                    )
                    fail(.unknownWorld(providerId: descriptor.id, world: target.world))
                    continue
                }
                if let pinnedWorld, world != pinnedWorld {
                    record(
                        .pinnedWorldMismatch,
                        world: target.world,
                        reason: "pinned world is \(pinnedWorld.rawValue)"
                    )
                    continue
                }
                guard descriptor.supportedWorlds.contains(world) else {
                    record(
                        .unsupportedWorld,
                        world: target.world,
                        reason: "provider does not support world \(target.world)"
                    )
                    if binding?.preferredProviderId == descriptor.id {
                        fail(.unsupportedWorld(providerId: descriptor.id, world: world))
                    }
                    continue
                }
                if !target.architectures.isEmpty {
                    let intersection = Set(target.architectures).intersection(descriptor.architectures)
                    if intersection.isEmpty {
                        record(
                            .unsupportedArchitecture,
                            world: target.world,
                            reason: "provider architectures \(descriptor.architectures.sorted()) do not match \(target.architectures)"
                        )
                        fail(.unsupportedArchitecture(
                            providerId: descriptor.id,
                            architecture: target.architectures[0]
                        ))
                        continue
                    }
                }
                if let unsupported = application.requiredCapabilities.first(
                    where: { !descriptor.capabilities.supports(capability: $0) }
                ) {
                    record(
                        .capabilityUnsupported,
                        world: target.world,
                        reason: "provider does not advertise \(unsupported)"
                    )
                    fail(.capabilityUnsupported(unsupported))
                    continue
                }
                let requiredQuotas = application.quotas?.requiredKinds ?? []
                if let missingQuota = requiredQuotas.first(
                    where: { !descriptor.enforcedQuotas.contains($0) }
                ) {
                    record(
                        .quotaUnenforceable,
                        world: target.world,
                        reason: "provider cannot enforce \(missingQuota.rawValue)"
                    )
                    fail(.quotaUnenforceable(providerId: descriptor.id, quota: missingQuota))
                    continue
                }
                guard descriptor.threadingProfiles.contains(threading) else {
                    record(
                        .synchronizationUnavailable,
                        world: target.world,
                        reason: "provider does not support \(threading.rawValue) threading"
                    )
                    fail(.synchronizationUnavailable(providerId: descriptor.id))
                    continue
                }
                record(
                    .eligible,
                    world: target.world,
                    reason: "passes device, availability, world, architecture, capability, quota and threading filters"
                )
                candidates.append(Candidate(
                    provider: provider,
                    world: world,
                    deviceId: effectiveDeviceId,
                    locationPriority: Self.locationPriority(descriptor.location),
                    preferred: binding?.preferredProviderId == descriptor.id
                ))
            }
        }

        guard let selected = candidates.sorted(by: {
            if $0.preferred != $1.preferred { return $0.preferred }
            if $0.locationPriority != $1.locationPriority {
                return $0.locationPriority < $1.locationPriority
            }
            if $0.provider.descriptor.id != $1.provider.descriptor.id {
                return $0.provider.descriptor.id < $1.provider.descriptor.id
            }
            return $0.world.rawValue < $1.world.rawValue
        }).first else {
            throw firstError ?? deviceMismatch ?? .noQualifiedProvider(applicationId: application.id)
        }

        let rationale = [
            "provider=\(selected.provider.descriptor.id)",
            "device=\(selected.deviceId ?? "(local)")",
            "world=\(selected.world.rawValue)",
            "location=\(selected.provider.descriptor.location.rawValue)",
            "threading=\(threading.rawValue)"
        ].joined(separator: "; ")

        let selectedDiagnostics = diagnostics.map { entry -> RuntimePlacementDiagnostic in
            guard entry.providerId == selected.provider.descriptor.id,
                  entry.world == selected.world.rawValue,
                  entry.outcome == .eligible else {
                return entry
            }
            var selectedEntry = entry
            selectedEntry.outcome = .selected
            selectedEntry.reason = "selected by preferred, local-first, provider id and world ordering"
            return selectedEntry
        }

        return RuntimeProviderSelection(
            providerId: selected.provider.descriptor.id,
            deviceId: selected.deviceId,
            world: selected.world,
            rationale: rationale,
            diagnostics: selectedDiagnostics
        )
    }

    static func standard(hostDeviceId: String? = nil) -> RuntimeRegistry {
        let registry = RuntimeRegistry(hostDeviceId: hostDeviceId)
        try? registry.register(WanixRuntimeProvider())
        try? registry.register(NativeRuntimeProvider())
        return registry
    }

    private static func locationPriority(_ location: RuntimeLocation) -> Int {
        switch location {
        case .phone: return 0
        case .castReceiver: return 1
        case .androidDevice: return 2
        case .remote: return 3
        }
    }
}
