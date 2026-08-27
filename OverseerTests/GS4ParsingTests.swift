//
//  GS4ParsingTests.swift
//  OverseerTests
//
//  Synthetic GS4 Query byte buffers, shaped like what Example Server
//  (203.0.113.10:25604) would actually return, so we can validate the
//  parser without a live socket.
//

import Testing
import Foundation
@testable import Overseer

/// Builds raw GS4 packet bytes from readable Swift values instead of
/// hand-computed hex, so the fixtures stay auditable.
private enum GS4Fixture {
    static func handshakeResponse(sessionID: Int32, token: Int32) -> Data {
        var bytes: [UInt8] = [GS4PacketType.handshake.rawValue]
        bytes += sessionID.bigEndianBytes
        bytes += Array(String(token).utf8)
        bytes += [0x00]
        return Data(bytes)
    }

    static func fullStatResponse(
        sessionID: Int32,
        keyValues: [(String, String)],
        players: [String]
    ) -> Data {
        var bytes: [UInt8] = [GS4PacketType.stat.rawValue]
        bytes += sessionID.bigEndianBytes
        // 11-byte fixed padding, per wiki.vg/Query: "splitnum" + \0 \x80 \0.
        // Built as raw bytes (not a Swift string) since 0x80 isn't valid
        // ASCII and would re-encode to two UTF-8 bytes if interpolated.
        bytes += Array("splitnum".utf8) + [0x00, 0x80, 0x00]

        for (key, value) in keyValues {
            bytes += Array(key.utf8) + [0x00]
            bytes += Array(value.utf8) + [0x00]
        }
        bytes += [0x00] // terminates the K/V section

        // 10-byte fixed padding ahead of the player list: \x01 + "player_" + \0 \0.
        bytes += [0x01] + Array("player_".utf8) + [0x00, 0x00]
        for player in players {
            bytes += Array(player.utf8) + [0x00]
        }
        bytes += [0x00] // terminates the player list

        return Data(bytes)
    }
}

@Suite("GS4 Query parsing")
struct GS4ParsingTests {

    @Test("Builds a well-formed handshake request")
    func handshakeRequestShape() {
        let request = GS4Protocol.handshakeRequest(sessionID: 0x0F0F0F0F)
        #expect([UInt8](request.prefix(2)) == [0xFE, 0xFD])
        #expect(request[request.startIndex + 2] == GS4PacketType.handshake.rawValue)
    }

    @Test("Parses a handshake response into its numeric challenge token")
    func parsesHandshakeToken() throws {
        let response = GS4Fixture.handshakeResponse(sessionID: 0x0F0F0F0F, token: 154_543_927)
        let token = try GS4Protocol.parseHandshakeResponse(response)
        #expect(token == 154_543_927)
    }

    @Test("Handshake response with a non-numeric token throws")
    func malformedHandshakeToken() {
        var bytes: [UInt8] = [GS4PacketType.handshake.rawValue]
        bytes += Int32(0x0F0F0F0F).bigEndianBytes
        bytes += Array("not-a-number".utf8) + [0x00]
        #expect(throws: GS4Error.malformedHandshakeResponse) {
            _ = try GS4Protocol.parseHandshakeResponse(Data(bytes))
        }
    }

    @Test("Parses a full-stat response shaped like Example Server's")
    func parsesFullStatResponse() throws {
        let response = GS4Fixture.fullStatResponse(
            sessionID: 0x0F0F0F0F,
            keyValues: [
                ("hostname", "Example Server - example.com"),
                ("gametype", "SMP"),
                ("game_id", "MINECRAFT"),
                ("version", "1.21.1"),
                ("map", "world"),
                ("numplayers", "3"),
                ("maxplayers", "40"),
                ("hostport", "25604"),
                ("hostip", "203.0.113.10")
            ],
            players: ["Alice", "Bob", "Steve"]
        )

        let stat = try GS4Protocol.parseFullStatResponse(response)

        #expect(stat.motd == "Example Server - example.com")
        #expect(stat.gameType == "SMP")
        #expect(stat.mapName == "world")
        #expect(stat.numPlayers == 3)
        #expect(stat.maxPlayers == 40)
        #expect(stat.hostPort == 25604)
        #expect(stat.hostIP == "203.0.113.10")
        #expect(stat.players == ["Alice", "Bob", "Steve"])
        #expect(stat.extraKeyValues["game_id"] == "MINECRAFT")
        #expect(stat.extraKeyValues["version"] == "1.21.1")
    }

    @Test("Parses an empty player list (server online, nobody on)")
    func parsesEmptyPlayerList() throws {
        let response = GS4Fixture.fullStatResponse(
            sessionID: 0x0F0F0F0F,
            keyValues: [
                ("hostname", "Example Server"),
                ("map", "world"),
                ("numplayers", "0"),
                ("maxplayers", "40")
            ],
            players: []
        )
        let stat = try GS4Protocol.parseFullStatResponse(response)
        #expect(stat.players.isEmpty)
        #expect(stat.numPlayers == 0)
    }

    @Test("Full-stat response with the wrong leading packet type throws")
    func wrongPacketType() {
        var bytes: [UInt8] = [GS4PacketType.handshake.rawValue] // wrong: should be .stat (0x00)
        bytes += Int32(0x0F0F0F0F).bigEndianBytes
        #expect(throws: GS4Error.unexpectedPacketType) {
            _ = try GS4Protocol.parseFullStatResponse(Data(bytes))
        }
    }

    @Test("Truncated full-stat response throws rather than crashing")
    func truncatedResponse() {
        var bytes: [UInt8] = [GS4PacketType.stat.rawValue]
        bytes += Int32(0x0F0F0F0F).bigEndianBytes
        bytes += [0x01, 0x02, 0x03] // cut off mid-padding, no K/V section at all
        #expect(throws: GS4Error.malformedStatResponse) {
            _ = try GS4Protocol.parseFullStatResponse(Data(bytes))
        }
    }
}
