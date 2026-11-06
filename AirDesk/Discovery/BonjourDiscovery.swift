import Foundation
import Network

struct DiscoveryBrowserEntry: Equatable, Sendable {
    let serviceName: String
    let txtData: Data
}

struct DiscoveryBrowserSnapshot: Equatable, Sendable {
    let serviceKind: DiscoveryServiceKind
    let entries: [DiscoveryBrowserEntry]
}

enum DiscoveryBrowserTransportEvent: Equatable, Sendable {
    case ready(DiscoveryServiceKind)
    case failed(DiscoveryServiceKind, String)
    case snapshot(DiscoveryBrowserSnapshot)
}

protocol DiscoveryBrowserTransport: AnyObject {
    func start(
        kinds: Set<DiscoveryServiceKind>,
        handler: @escaping (DiscoveryBrowserTransportEvent) -> Void
    )
    func stop()
}

struct DiscoveredAdvertisement: Equatable, Sendable {
    let serviceName: String
    let advertisement: DiscoveryAdvertisement
}

final class DiscoveryBrowser {
    enum State: Equatable, Sendable {
        case idle
        case browsing
        case failed(String)
    }

    private let transport: DiscoveryBrowserTransport
    private let lock = NSLock()
    private var stateByKind: [DiscoveryServiceKind: State] = [:]
    private var advertisementsByKind: [DiscoveryServiceKind: [String: DiscoveryAdvertisement]] = [:]
    private var onChange: (([DiscoveredAdvertisement]) -> Void)?

    init(transport: DiscoveryBrowserTransport = NWBrowserDiscoveryTransport()) {
        self.transport = transport
    }

    var advertisements: [DiscoveredAdvertisement] {
        lock.lock()
        defer { lock.unlock() }
        return snapshotLocked()
    }

    func state(for kind: DiscoveryServiceKind) -> State {
        lock.lock()
        defer { lock.unlock() }
        return stateByKind[kind] ?? .idle
    }

    func start(
        kinds: Set<DiscoveryServiceKind> = Set(DiscoveryServiceKind.allCases),
        onChange: @escaping ([DiscoveredAdvertisement]) -> Void
    ) {
        transport.stop()
        lock.lock()
        stateByKind = Dictionary(uniqueKeysWithValues: kinds.map { ($0, .idle) })
        advertisementsByKind = [:]
        self.onChange = onChange
        lock.unlock()

        transport.start(kinds: kinds) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        transport.stop()
        lock.lock()
        stateByKind = [:]
        advertisementsByKind = [:]
        onChange = nil
        lock.unlock()
    }

    private func handle(_ event: DiscoveryBrowserTransportEvent) {
        lock.lock()
        switch event {
        case .ready(let kind):
            stateByKind[kind] = .browsing
        case .failed(let kind, let reason):
            stateByKind[kind] = .failed(reason)
            advertisementsByKind[kind] = [:]
        case .snapshot(let snapshot):
            var decoded: [String: DiscoveryAdvertisement] = [:]
            for entry in snapshot.entries {
                guard let txt = try? DiscoveryTXTRecord(txtData: entry.txtData) else { continue }
                decoded[entry.serviceName] = DiscoveryAdvertisement(
                    serviceKind: snapshot.serviceKind,
                    txt: txt
                )
            }
            advertisementsByKind[snapshot.serviceKind] = decoded
        }
        let snapshot = snapshotLocked()
        let callback = onChange
        lock.unlock()
        callback?(snapshot)
    }

    private func snapshotLocked() -> [DiscoveredAdvertisement] {
        advertisementsByKind
            .flatMap { kind, entries in
                entries.map { name, advertisement in
                    DiscoveredAdvertisement(serviceName: name, advertisement: advertisement)
                }
            }
            .sorted {
                if $0.advertisement.serviceKind.rawValue == $1.advertisement.serviceKind.rawValue {
                    return $0.serviceName < $1.serviceName
                }
                return $0.advertisement.serviceKind.rawValue < $1.advertisement.serviceKind.rawValue
            }
    }
}

final class NWBrowserDiscoveryTransport: DiscoveryBrowserTransport {
    private let queue = DispatchQueue(label: "com.airdesk.discovery.browser")
    private var browsers: [DiscoveryServiceKind: NWBrowser] = [:]

    func start(
        kinds: Set<DiscoveryServiceKind>,
        handler: @escaping (DiscoveryBrowserTransportEvent) -> Void
    ) {
        stop()
        for kind in kinds {
            let descriptor = NWBrowser.Descriptor.bonjour(
                type: kind.serviceType,
                domain: kind.domain
            )
            let parameters: NWParameters = kind == .control ? .tcp : .udp
            let browser = NWBrowser(for: descriptor, using: parameters)
            browser.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    handler(.ready(kind))
                case .failed(let error):
                    handler(.failed(kind, error.localizedDescription))
                case .cancelled:
                    break
                default:
                    break
                }
            }
            browser.browseResultsChangedHandler = { results, _ in
                let entries = results
                    .compactMap(Self.entry)
                    .sorted { $0.serviceName < $1.serviceName }
                handler(.snapshot(DiscoveryBrowserSnapshot(
                    serviceKind: kind,
                    entries: entries
                )))
            }
            browsers[kind] = browser
            browser.start(queue: queue)
        }
    }

    func stop() {
        for browser in browsers.values {
            browser.cancel()
        }
        browsers.removeAll()
    }

    private static func entry(from result: NWBrowser.Result) -> DiscoveryBrowserEntry? {
        guard case let .service(name, _, _, _) = result.endpoint else { return nil }
        let txtData: Data
        switch result.metadata {
        case .bonjour(let txt):
            txtData = Self.encodeTXT(txt)
        case .none:
            txtData = Data()
        @unknown default:
            return nil
        }
        return DiscoveryBrowserEntry(serviceName: name, txtData: txtData)
    }

    private static func encodeTXT(_ record: NWTXTRecord) -> Data {
        var data = Data()
        for (key, value) in record.dictionary.sorted(by: { $0.key < $1.key }) {
            let item = Data("\(key)=\(value)".utf8)
            guard item.count <= 255 else { continue }
            data.append(UInt8(item.count))
            data.append(item)
        }
        return data
    }
}

final class NWDiscoveryPublisher {
    private let queue = DispatchQueue(label: "com.airdesk.discovery.publisher")
    private var listeners: [DiscoveryServiceKind: NWListener] = [:]

    func start(name: String, advertisements: [DiscoveryAdvertisement]) throws {
        stop()
        for advertisement in advertisements {
            let parameters: NWParameters = advertisement.serviceKind == .control ? .tcp : .udp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(
                name: name,
                type: advertisement.serviceType,
                domain: advertisement.domain,
                txtRecord: advertisement.txt.encoded()
            )
            listener.newConnectionHandler = { connection in
                connection.cancel()
            }
            listeners[advertisement.serviceKind] = listener
            listener.start(queue: queue)
        }
    }

    func stop() {
        for listener in listeners.values {
            listener.cancel()
        }
        listeners.removeAll()
    }
}
