//
//  GzipTests.swift
//  OverseerTests
//
//  Fixtures below are real gzip output (`gzip` CLI, not hand-rolled),
//  covering both the plain fixed-header case and one with the optional
//  FNAME field set, for the plaintext:
//    "Hello, NBT world! This is a test payload for gzip decompression testing 1234567890."
//

import Foundation
import Testing
@testable import Overseer

@Suite("Gzip")
struct GzipTests {

    private static let expectedPlaintext =
        "Hello, NBT world! This is a test payload for gzip decompression testing 1234567890."

    private static func hexData(_ hex: String) -> Data {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return data
    }

    // `gzip -n` output — no optional header fields set.
    private static let plainFixture = hexData(
        "1f8b0800000000000003f348cdc9c9d751f0730a5128cf2fca49515408c9c82c5600a2448592d4e2128582c4ca9cfcc" +
        "41485b4fc2285f4aacc028594d4e4fcdc82a2d4e2e2ccfc3cb09accbc7405432363135333730b4b033d00409df71053000000"
    )

    // `gzip` default output — FNAME set ("nbt_test.bin").
    private static let withNameFixture = hexData(
        "1f8b080837ac756a00036e62745f746573742e62696e00f348cdc9c9d751f0730a5128cf2fca49515408c9c82c5600" +
        "a2448592d4e2128582c4ca9cfcc41485b4fc2285f4aacc028594d4e4fcdc82a2d4e2e2ccfc3cb09accbc7405432363135" +
        "333730b4b033d00409df71053000000"
    )

    @Test("Detects gzip magic bytes")
    func detectsGzipMagic() {
        #expect(Gzip.isGzipped(Self.plainFixture))
        #expect(!Gzip.isGzipped(Data([0x00, 0x01, 0x02])))
        #expect(!Gzip.isGzipped(Data([0x1f])))  // too short to check the second magic byte
    }

    @Test("Decompresses a plain gzip stream (no optional header fields) against real gzip output")
    func decompressesPlainStream() throws {
        let decompressed = try Gzip.decompress(Self.plainFixture)
        #expect(String(decoding: decompressed, as: UTF8.self) == Self.expectedPlaintext)
    }

    @Test("Decompresses a gzip stream with the FNAME header field set")
    func decompressesStreamWithFilename() throws {
        let decompressed = try Gzip.decompress(Self.withNameFixture)
        #expect(String(decoding: decompressed, as: UTF8.self) == Self.expectedPlaintext)
    }

    @Test("Throws on non-gzip input rather than crashing")
    func throwsOnNonGzipInput() {
        #expect(throws: GzipError.notGzipped) {
            _ = try Gzip.decompress(Data([0x00, 0x01, 0x02, 0x03]))
        }
    }
}
