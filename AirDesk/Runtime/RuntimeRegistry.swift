import Foundation

final class RuntimeRegistry {
    private struct Candidate {
        var provider: any RuntimeProvider
        var world: RuntimeWorld
        var locationPriority: Int
        var preferred: Bool
    }

    private var providersByID: [String: any RuntimeProvider] = [:]
    private let lock = NSLock()

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
        let providers = Array(providersByID.values)
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
        var firstError: RuntimeProviderError?

        for provider in providers {
            let descriptor = provider.descriptor
            guard descriptor.availability == .available else {
                if binding?.preferredProviderId == descriptor.id {
                    firstError = .providerUnavailable(descriptor.id)
                } else if placement?.providerId == descriptor.id {
                    firstError = .providerUnavailable(descriptor.id)
                }
                continue
            }
            guard descriptor.health != .open else {
                if binding?.preferredProviderId == descriptor.id {
                    firstError = .providerUnavailable(descriptor.id)
                }
                continue
            }
            if let providerID = placement?.providerId, providerID != descriptor.id {
                continue
            }
            if let preferred = binding?.preferredProviderId, !preferred.isEmpty {
                if binding?.fallbackPolicy == .deny, preferred != descriptor.id {
                    continue
                }
                if binding?.fallbackPolicy == .localOnly && descriptor.location == .remote {
                    continue
                }
            }

            for target in application.runtimeTargets where target.provider == descriptor.id {
                guard let world = RuntimeWorld(rawValue: target.world) else {
                    firstError = .unknownWorld(providerId: descriptor.id, world: target.world)
                    continue
                }
                if let pinnedWorld, world != pinnedWorld { continue }
                guard descriptor.supportedWorlds.contains(world) else {
                    if binding?.preferredProviderId == descriptor.id {
                        firstError = .unsupportedWorld(providerId: descriptor.id, world: world)
                    }
                    continue
                }
                if !target.architectures.isEmpty {
                    let intersection = Set(target.architectures).intersection(descriptor.architectures)
                    if intersection.isEmpty {
                        firstError = .unsupportedArchitecture(
                            providerId: descriptor.id,
                            architecture: target.architectures[0]
                        )
                        continue
                    }
                }
                if let unsupported = application.requiredCapabilities.first(
                    where: { !descriptor.capabilities.supports(capability: $0) }
                ) {
                    firstError = .capabilityUnsupported(unsupported)
                    continue
                }
                let requiredQuotas = application.quotas?.requiredKinds ?? []
                if let missingQuota = requiredQuotas.first(
                    where: { !descriptor.enforcedQuotas.contains($0) }
                ) {
                    firstError = .quotaUnenforceable(providerId: descriptor.id, quota: missingQuota)
                    continue
                }
                guard descriptor.threadingProfiles.contains(threading) else {
                    firstError = .synchronizationUnavailable(providerId: descriptor.id)
                    continue
                }
                candidates.append(Candidate(
                    provider: provider,
                    world: world,
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
            throw firstError ?? .noQualifiedProvider(applicationId: application.id)
        }

        let rationale = [
            "provider=\(selected.provider.descriptor.id)",
            "world=\(selected.world.rawValue)",
            "location=\(selected.provider.descriptor.location.rawValue)",
            "threading=\(threading.rawValue)"
        ].joined(separator: "; ")

        return RuntimeProviderSelection(
            providerId: selected.provider.descriptor.id,
            world: selected.world,
            rationale: rationale
        )
    }

    static func standard() -> RuntimeRegistry {
        let registry = RuntimeRegistry()
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
