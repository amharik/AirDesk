import Foundation
import XCTest
@testable import AirDesk

final class ResourceCompoundCodecTests: XCTestCase {
    private static let compoundURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("protocol/fixtures/resource-compound/walk-open-read-clunk-v1.json")
    private static let blobURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("protocol/fixtures/resource-blob/blake3-handle-v1.json")

    private var compound: [String: Any]!
    private var blobFile: [String: Any]!

    override func setUpWithError() throws {
        compound = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: Self.compoundURL)) as? [String: Any]
        )
        blobFile = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: Self.blobURL)) as? [String: Any]
        )
    }

    func testCompoundRequestFixtureDecodesAndReencodes() throws {
        let fixture = try dictionary("request", in: compound)
        let bytes = try data(hex: XCTUnwrap(fixture["hex"] as? String))
        let decoded = try ResourceCompoundCodec.decodeCompoundRequest(bytes)

        XCTAssertEqual(decoded.requestId, 42)
        XCTAssertEqual(decoded.fid, 7)
        XCTAssertEqual(decoded.newFid, 8)
        XCTAssertEqual(decoded.wnames, ["documents", "notes.txt"])
        XCTAssertEqual(decoded.openMode, .readOnly)
        XCTAssertEqual(decoded.readOffset, 0)
        XCTAssertEqual(decoded.readCount, 32)
        XCTAssertTrue(decoded.clunk)
        XCTAssertEqual(try ResourceCompoundCodec.encodeCompoundRequest(decoded), bytes)
    }

    func testInlineCompoundResultFixtureDecodesAndReencodes() throws {
        let fixture = try dictionary("result", in: compound)
        let bytes = try data(hex: XCTUnwrap(fixture["hex"] as? String))
        let decoded = try ResourceCompoundCodec.decodeCompoundResult(bytes)

        XCTAssertEqual(decoded.requestId, 42)
        XCTAssertEqual(decoded.status, .ok)
        XCTAssertEqual(decoded.qid, ResourceQid(type: 0, version: 3, path: 987_654_321))
        XCTAssertEqual(decoded.iounit, 65_536)
        XCTAssertEqual(decoded.data, Data("hello from compound read\n".utf8))
        XCTAssertNil(decoded.blob)
        XCTAssertEqual(decoded.stat?.qid, ResourceQid(type: 0, version: 3, path: 987_654_321))
        XCTAssertEqual(decoded.stat?.mode, 33_188)
        XCTAssertEqual(decoded.stat?.length, 25)
        XCTAssertEqual(decoded.stat?.name, "notes.txt")
        XCTAssertEqual(decoded.stat?.modifiedAt, 1_700_000_000_123)
        XCTAssertEqual(decoded.clunkStatus, .ok)
        XCTAssertEqual(try ResourceCompoundCodec.encodeCompoundResult(decoded), bytes)
    }

    func testLargeCompoundResultReturnsVersionedBlake3Handle() throws {
        let fixture = try dictionary("blobResult", in: compound)
        let bytes = try data(hex: XCTUnwrap(fixture["hex"] as? String))
        let decoded = try ResourceCompoundCodec.decodeCompoundResult(bytes)

        XCTAssertTrue(decoded.data.isEmpty)
        XCTAssertNil(decoded.stat)
        let blob = try XCTUnwrap(decoded.blob)
        XCTAssertEqual(blob.version, ResourceCompoundCodec.blobHandleVersion)
        XCTAssertEqual(blob.algorithm, .blake3)
        XCTAssertEqual(blob.digest.count, ResourceCompoundCodec.blake3DigestBytes)
        XCTAssertEqual(blob.digest, try data(hex: "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"))
        XCTAssertEqual(blob.length, 131_072)
        XCTAssertEqual(blob.expiresAt, 1_700_000_600_000)
        XCTAssertEqual(try ResourceCompoundCodec.encodeCompoundResult(decoded), bytes)
    }

    func testReadResultFixturesDecodeAndReencode() throws {
        let blobFixture = try dictionary("blob", in: blobFile)
        let blobBytes = try data(hex: XCTUnwrap(blobFixture["hex"] as? String))
        let large = try ResourceCompoundCodec.decodeReadResult(blobBytes)
        XCTAssertTrue(large.data.isEmpty)
        XCTAssertEqual(large.blob?.length, 131_072)
        XCTAssertEqual(try ResourceCompoundCodec.encodeReadResult(large), blobBytes)

        let smallFixture = try dictionary("smallRead", in: blobFile)
        let smallBytes = try data(hex: XCTUnwrap(smallFixture["hex"] as? String))
        let small = try ResourceCompoundCodec.decodeReadResult(smallBytes)
        XCTAssertEqual(small.data, Data("small payload".utf8))
        XCTAssertNil(small.blob)
        XCTAssertEqual(try ResourceCompoundCodec.encodeReadResult(small), smallBytes)
    }

    func testRejectsOversizedAndAmbiguousResults() throws {
        let digest = try data(hex: "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262")
        let blob = ResourceBlobHandle(
            version: 1,
            algorithm: .blake3,
            digest: digest,
            length: 131_072,
            expiresAt: 0
        )

        XCTAssertThrowsError(
            try ResourceCompoundCodec.encodeCompoundResult(
                ResourceCompoundResultPayload(
                    requestId: 1,
                    status: .ok,
                    qid: nil,
                    iounit: 65_536,
                    data: Data(repeating: 0, count: ResourceCompoundCodec.inlineLimit + 1),
                    blob: nil,
                    stat: nil,
                    clunkStatus: .ok
                )
            )
        ) { error in
            XCTAssertEqual(error as? ResourceCompoundError, .inlineTooLarge)
        }

        XCTAssertThrowsError(
            try ResourceCompoundCodec.encodeReadResult(
                ResourceReadResultPayload(data: Data([1]), blob: blob)
            )
        ) { error in
            XCTAssertEqual(error as? ResourceCompoundError, .ambiguousPayload)
        }

        XCTAssertThrowsError(
            try ResourceCompoundCodec.validateBlobHandle(
                ResourceBlobHandle(
                    version: 1,
                    algorithm: .blake3,
                    digest: digest.dropLast(),
                    length: 1,
                    expiresAt: 0
                )
            )
        ) { error in
            XCTAssertEqual(error as? ResourceCompoundError, .invalidBlobDigest)
        }
    }

    func testRejectsUnsafePathSegments() throws {
        let base = ResourceCompoundRequestPayload(
            requestId: 1,
            fid: 1,
            newFid: 2,
            wnames: [".."],
            openMode: .readOnly,
            readOffset: 0,
            readCount: 0,
            clunk: true
        )
        XCTAssertThrowsError(try ResourceCompoundCodec.encodeCompoundRequest(base))

        var slash = base
        slash.wnames = ["a/b"]
        XCTAssertThrowsError(try ResourceCompoundCodec.encodeCompoundRequest(slash)) { error in
            XCTAssertEqual(error as? ResourceCompoundError, .invalidPathSegment)
        }

        var tooMany = base
        tooMany.wnames = Array(repeating: "x", count: ResourceCompoundCodec.maxPathSegments + 1)
        XCTAssertThrowsError(try ResourceCompoundCodec.encodeCompoundRequest(tooMany)) { error in
            XCTAssertEqual(error as? ResourceCompoundError, .tooManyPathSegments)
        }
    }

    func testRejectsWrongPayloadAndMalformedData() throws {
        let requestFixture = try dictionary("request", in: compound)
        let requestBytes = try data(hex: XCTUnwrap(requestFixture["hex"] as? String))
        XCTAssertThrowsError(try ResourceCompoundCodec.decodeReadResult(requestBytes)) { error in
            XCTAssertEqual(error as? ResourceCompoundError, .wrongPayload)
        }

        XCTAssertThrowsError(try ResourceCompoundCodec.decodeCompoundResult(Data([0xFF, 0xFF, 0xFF, 0xFF]))) { error in
            XCTAssertEqual(error as? ResourceCompoundError, .invalidFlatBuffer)
        }
    }

    private func dictionary(_ key: String, in source: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(source[key] as? [String: Any])
    }

    private func data(hex: String) throws -> Data {
        var result = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                throw ResourceCompoundError.invalidFlatBuffer
            }
            result.append(byte)
            index = next
        }
        return result
    }
}
