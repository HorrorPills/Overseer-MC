//
//  VarIntTests.swift
//  OverseerTests
//

import Testing
@testable import Overseer

@Suite("VarInt")
struct VarIntTests {

    @Test("Encodes single-byte values", arguments: [0, 1, 2, 15, 127])
    func encodesSingleByte(_ value: Int32) {
        let bytes = VarInt.encode(value)
        #expect(bytes.count == 1)
        #expect(bytes[0] == UInt8(value))
    }

    @Test("Known reference vectors from wiki.vg round-trip")
    func referenceVectors() throws {
        let vectors: [(Int32, [UInt8])] = [
            (0, [0x00]),
            (1, [0x01]),
            (2, [0x02]),
            (127, [0x7f]),
            (128, [0x80, 0x01]),
            (255, [0xff, 0x01]),
            (25604, [0x84, 0xC8, 0x01]), // Example Server's port, for good measure
            (2097151, [0xff, 0xff, 0x7f]),
            (-1, [0xff, 0xff, 0xff, 0xff, 0x0f]),
            (Int32.min, [0x80, 0x80, 0x80, 0x80, 0x08])
        ]
        for (value, expectedBytes) in vectors {
            #expect(VarInt.encode(value) == expectedBytes, "encode(\(value))")
            var offset = 0
            let decoded = try VarInt.decode(expectedBytes, offset: &offset)
            #expect(decoded == value, "decode(\(expectedBytes))")
            #expect(offset == expectedBytes.count)
        }
    }

    @Test("Round-trips arbitrary values")
    func roundTrips() throws {
        for value: Int32 in [-2_000_000_000, -1, 0, 1, 300, 70000, 2_000_000_000] {
            let encoded = VarInt.encode(value)
            var offset = 0
            let decoded = try VarInt.decode(encoded, offset: &offset)
            #expect(decoded == value)
        }
    }

    @Test("Throws truncated on an incomplete buffer")
    func truncatedBuffer() {
        var offset = 0
        // 0x80 signals "more bytes follow" but the buffer ends there.
        #expect(throws: VarIntError.truncated) {
            _ = try VarInt.decode([0x80], offset: &offset)
        }
    }

    @Test("Throws tooLong on a buffer with too many continuation bytes")
    func tooLongBuffer() {
        var offset = 0
        #expect(throws: VarIntError.tooLong) {
            _ = try VarInt.decode([0x80, 0x80, 0x80, 0x80, 0x80, 0x01], offset: &offset)
        }
    }

    @Test("String encode/decode round trip")
    func stringRoundTrip() throws {
        let strings = ["", "example.com", "🎮 unicode name"]
        for string in strings {
            let encoded = VarInt.encodeString(string)
            var offset = 0
            let decoded = try VarInt.decodeString(encoded, offset: &offset)
            #expect(decoded == string)
            #expect(offset == encoded.count)
        }
    }
}
