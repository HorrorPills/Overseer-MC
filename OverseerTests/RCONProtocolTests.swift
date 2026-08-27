//
//  RCONProtocolTests.swift
//  OverseerTests
//
//  Source RCON packet encode/decode, including fragmentation
//  reassembly (a large response split across several TCP reads/packets)
//  against synthetic byte buffers — no live socket.
//

import Testing
import Foundation
@testable import Overseer

@Suite("RCON packet encode/decode")
struct RCONProtocolTests {

    @Test("Encodes the exact wire layout: LE length, reqID, type, payload, two null terminators")
    func encodesExpectedLayout() {
        let packet = RCONPacket(requestID: 7, type: 2, payload: "list")
        let bytes = [UInt8](packet.encoded())

        // Length = reqID(4) + type(4) + "list"(4) + null(1) + pad(1) = 14
        #expect(bytes.count == 4 + 14)
        #expect(Int32(littleEndianBytes: Array(bytes[0..<4])) == 14)
        #expect(Int32(littleEndianBytes: Array(bytes[4..<8])) == 7)
        #expect(Int32(littleEndianBytes: Array(bytes[8..<12])) == 2)
        #expect(Array(bytes[12..<16]) == Array("list".utf8))
        #expect(bytes[16] == 0x00) // payload terminator
        #expect(bytes[17] == 0x00) // pad
    }

    @Test("Round-trips through decode")
    func roundTrips() throws {
        let original = RCONPacket(requestID: 42, type: 0, payload: "Whitelisted players: Alice, Bob")
        var buffer = original.encoded()
        let decoded = try RCONPacketDecoder.decodeNext(from: &buffer)
        #expect(decoded == original)
        #expect(buffer.isEmpty) // fully consumed
    }

    @Test("Returns nil when the buffer doesn't yet contain a full packet")
    func returnsNilOnPartialBuffer() throws {
        let full = RCONPacket(requestID: 1, type: 2, payload: "hello world").encoded()
        var partial = full.prefix(full.count - 1) // one byte short
        let result = try RCONPacketDecoder.decodeNext(from: &partial)
        #expect(result == nil)
        #expect(partial.count == full.count - 1) // untouched
    }

    @Test("Reassembles a response split across multiple decode calls fed incrementally")
    func reassemblesFragmentedStream() throws {
        // Simulate three separate packets (as if a large /whitelist list
        // response were split by the server) arriving as one combined
        // byte stream, then fed to the decoder in small chunks — mimics
        // TCP not respecting packet boundaries.
        let packets = [
            RCONPacket(requestID: 5, type: 0, payload: "Alice, "),
            RCONPacket(requestID: 5, type: 0, payload: "Bob, "),
            RCONPacket(requestID: 5, type: 0, payload: "Steve"),
            RCONPacket(requestID: 6, type: 0, payload: "") // the empty-command end marker
        ]
        let stream = packets.reduce(Data()) { $0 + $1.encoded() }

        var buffer = Data()
        var decoded: [RCONPacket] = []
        // Feed the stream in arbitrary 3-byte chunks to exercise the
        // "not enough bytes yet" path repeatedly.
        for chunk in stride(from: 0, to: stream.count, by: 3) {
            let end = min(chunk + 3, stream.count)
            buffer.append(stream[chunk..<end])
            while let packet = try RCONPacketDecoder.decodeNext(from: &buffer) {
                decoded.append(packet)
            }
        }

        #expect(decoded == packets)

        // Reassembling per the RCONClient.execute() convention: everything
        // with the command's request ID, up to the marker's request ID.
        let reassembled = decoded
            .prefix { $0.requestID != 6 }
            .filter { $0.requestID == 5 }
            .map(\.payload)
            .joined()
        #expect(reassembled == "Alice, Bob, Steve")
    }

    @Test("Throws malformedPacket on an implausibly short declared length")
    func rejectsImplausiblyShortLength() {
        var buffer = Data(Int32(4).littleEndianBytes) // declares length 4, below the 10-byte minimum
        #expect(throws: RCONClient.RCONError.malformedPacket) {
            _ = try RCONPacketDecoder.decodeNext(from: &buffer)
        }
    }

    @Test("Int32 little-endian byte round trip")
    func littleEndianRoundTrip() {
        for value: Int32 in [0, 1, -1, 25605, Int32.max, Int32.min] {
            let bytes = value.littleEndianBytes
            #expect(bytes.count == 4)
            #expect(Int32(littleEndianBytes: bytes) == value)
        }
    }
}
