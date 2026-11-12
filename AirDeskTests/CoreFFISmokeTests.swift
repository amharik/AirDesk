import XCTest
import AirDeskCore
@testable import AirDesk

#if AIRDESK_CORE_SMOKE
final class CoreFFISmokeTests: XCTestCase {
    func testGeneratedCoreSmokeSurface() {
        XCTAssertEqual(CoreFFISmoke.label, "airdesk-core/1")
        XCTAssertEqual(CoreFFISmoke.abiVersion, 1)
        XCTAssertTrue(CoreFFISmoke.isCurrentABICompatible)
    }

    func testGeneratedSpake2PlusRegistrationMatchesVector() throws {
        let w1 = try hex("7e945f34d78785b8a3ef44d0df5a1a97d6b3b460409a345ca7830387a74b1dba")
        let expected = try hex(
            "04eb7c9db3d9a9eb1f8adab81b5794c1f13ae3e225efbe91ea487425854c7fc00f00bfedcbd09b2400142d40a14f2064ef31dfaa903b91d1faea7093d835966efd"
        )
        XCTAssertEqual(try coreSpake2plusRegistrationRecord(w1: w1), expected)
    }

    private func hex(_ value: String) throws -> Data {
        guard value.count.isMultiple(of: 2) else {
            throw NSError(domain: "CoreFFISmokeTests", code: 1)
        }
        var data = Data()
        data.reserveCapacity(value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else {
                throw NSError(domain: "CoreFFISmokeTests", code: 2)
            }
            data.append(byte)
            index = next
        }
        return data
    }
}
#endif
