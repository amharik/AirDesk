import Foundation

enum DiscoveryServiceKind: String, CaseIterable, Hashable, Sendable {
    case control
    case webTransport

    var serviceType: String {
        switch self {
        case .control: return "_airdesk._tcp"
        case .webTransport: return "_airdesk._udp"
        }
    }

    var domain: String { "local." }

    var fullServiceName: String { "\(serviceType).\(domain)" }
}

enum DiscoveryDeviceType: String, CaseIterable, Sendable {
    case host
    case controller
    case display
}

enum DiscoveryAdvertisementError: Error, Equatable {
    case unsupportedKey(String)
    case forbiddenKey(String)
    case missingKey(String)
    case duplicateKey(String)
    case invalidValue(String)
    case invalidVersion(String)
    case invalidCertificateHash(String)
    case malformedTXT
}

struct DiscoveryTXTRecord: Equatable, Sendable {
    static let txtVersion = "1"
    static let protocolVersion = "1.0"

    let deviceType: DiscoveryDeviceType
    let currentCertificateHash: String
    let nextCertificateHash: String?

    init(
        deviceType: DiscoveryDeviceType,
        currentCertificateHash: String,
        nextCertificateHash: String? = nil
    ) throws {
        self.deviceType = deviceType
        self.currentCertificateHash = try Self.canonicalCertificateHash(currentCertificateHash)
        if let nextCertificateHash {
            let next = try Self.canonicalCertificateHash(nextCertificateHash)
            guard next != self.currentCertificateHash else {
                throw DiscoveryAdvertisementError.invalidCertificateHash("next hash matches current")
            }
            self.nextCertificateHash = next
        } else {
            self.nextCertificateHash = nil
        }
    }

    init(txtData: Data) throws {
        let bytes = [UInt8](txtData)
        var index = 0
        var values: [String: String] = [:]

        while index < bytes.count {
            let length = Int(bytes[index])
            index += 1
            guard length > 0, index + length <= bytes.count else {
                throw DiscoveryAdvertisementError.malformedTXT
            }
            let item = Data(bytes[index..<(index + length)])
            guard
                let text = String(data: item, encoding: .utf8),
                let separator = text.firstIndex(of: "=")
            else {
                throw DiscoveryAdvertisementError.malformedTXT
            }
            let key = String(text[..<separator])
            let value = String(text[text.index(after: separator)...])
            guard !key.isEmpty, !value.isEmpty else {
                throw DiscoveryAdvertisementError.malformedTXT
            }
            guard values[key] == nil else {
                throw DiscoveryAdvertisementError.duplicateKey(key)
            }
            values[key] = value
            index += length
        }

        try self.init(dictionary: values)
    }

    init(dictionary: [String: String]) throws {
        let allowed: Set<String> = [
            "txtvers",
            "adfp_ver",
            "device_type",
            "certhash_current",
            "certhash_next"
        ]
        let forbidden: Set<String> = ["dev_id", "role_mask"]

        for key in dictionary.keys {
            if forbidden.contains(key) {
                throw DiscoveryAdvertisementError.forbiddenKey(key)
            }
            if !allowed.contains(key) {
                throw DiscoveryAdvertisementError.unsupportedKey(key)
            }
        }

        let txtVersion = try Self.required("txtvers", in: dictionary)
        guard txtVersion == Self.txtVersion else {
            throw DiscoveryAdvertisementError.invalidVersion(txtVersion)
        }
        let protocolVersion = try Self.required("adfp_ver", in: dictionary)
        guard protocolVersion == Self.protocolVersion else {
            throw DiscoveryAdvertisementError.invalidVersion(protocolVersion)
        }

        let typeValue = try Self.required("device_type", in: dictionary)
        guard let deviceType = DiscoveryDeviceType(rawValue: typeValue) else {
            throw DiscoveryAdvertisementError.invalidValue("device_type")
        }

        try self.init(
            deviceType: deviceType,
            currentCertificateHash: try Self.required("certhash_current", in: dictionary),
            nextCertificateHash: dictionary["certhash_next"]
        )
    }

    var dictionary: [String: String] {
        var values = [
            "txtvers": Self.txtVersion,
            "adfp_ver": Self.protocolVersion,
            "device_type": deviceType.rawValue,
            "certhash_current": currentCertificateHash
        ]
        if let nextCertificateHash {
            values["certhash_next"] = nextCertificateHash
        }
        return values
    }

    func encoded() -> Data {
        let pairs = Self.canonicalKeys.compactMap { key in
            dictionary[key].map { (key, $0) }
        }
        var data = Data()
        for (key, value) in pairs {
            let item = Data("\(key)=\(value)".utf8)
            guard item.count <= 255 else { continue }
            data.append(UInt8(item.count))
            data.append(item)
        }
        return data
    }

    private static let canonicalKeys = [
        "txtvers",
        "adfp_ver",
        "device_type",
        "certhash_current",
        "certhash_next"
    ]

    private static func required(
        _ key: String,
        in dictionary: [String: String]
    ) throws -> String {
        guard let value = dictionary[key], !value.isEmpty else {
            throw DiscoveryAdvertisementError.missingKey(key)
        }
        return value
    }

    private static func canonicalCertificateHash(_ value: String) throws -> String {
        guard value.count == 64, value.allSatisfy(\.isHexDigit) else {
            throw DiscoveryAdvertisementError.invalidCertificateHash(value)
        }
        return value.lowercased()
    }
}

struct DiscoveryAdvertisement: Equatable, Sendable {
    let serviceKind: DiscoveryServiceKind
    let txt: DiscoveryTXTRecord

    var serviceType: String { serviceKind.serviceType }
    var domain: String { serviceKind.domain }
    var fullServiceName: String { serviceKind.fullServiceName }
}
