import XCTest
@testable import AirDesk

final class NativeP256Tests: XCTestCase {
    func testRoundTripsGeneratorAndCompressedConstants() throws {
        let group = try NativeP256Group()
        let generator = try group.generator()
        let encoded = try group.encode(generator)
        XCTAssertEqual(encoded.count, 65)
        XCTAssertEqual(encoded.first, 0x04)
        XCTAssertEqual(try group.encode(group.decode(encoded)), encoded)

        let m = try group.decode(
            try XCTUnwrap(Data(hexString: "02886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f")),
            requireUncompressed: false
        )
        XCTAssertEqual(try group.encode(m).first, 0x04)
    }

    func testRejectsMalformedAndIdentityPoints() throws {
        let group = try NativeP256Group()
        XCTAssertThrowsError(try group.decode(Data([0x00])))
        XCTAssertThrowsError(try group.decode(Data(repeating: 0, count: 65)))
        XCTAssertThrowsError(try group.decode(Data(repeating: 0, count: 64)))
    }

    func testRejectsOutOfRangeScalars() throws {
        let group = try NativeP256Group()
        let generator = try group.generator()
        XCTAssertThrowsError(try group.multiply(generator, by: Data(repeating: 0, count: 32)))
        XCTAssertThrowsError(try group.multiply(generator, by: Data(repeating: 0xff, count: 32)))
        let one = Data(repeating: 0, count: 31) + Data([1])
        XCTAssertEqual(try group.encode(group.multiply(generator, by: one)), try group.encode(generator))
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
