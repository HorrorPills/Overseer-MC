//
//  GS4Query.swift
//  Overseer
//
//  GameSpy4 (GS4) Query protocol, as implemented by vanilla/Paper's
//  `enable-query=true` listener. This is the UDP protocol that gives us
//  the *un-sampled* player list (Server List Ping only ever returns a
//  truncated `sample` array), MOTD, map name, and max slots.
//
//  Reference: https://wiki.vg/Query
//
//  Two-stage handshake:
//   1. Handshake request  -> server replies with an ASCII decimal
//      "challenge token" string, null-terminated.
//   2. Full stat request (token + 4 bytes of zero padding to select the
//      "full" rather than "basic" stat) -> server replies with a
//      K/V section (motd, gametype, map, numplayers, maxplayers, ...)
//      followed by a player-name list section.
//
//  All packet building / parsing here is pure (no networking), so it is
//  directly unit-testable against synthetic byte buffers.
//

import Foundation

enum GS4Error: Error, Equatable {
    case malformedHandshakeResponse
    case malformedStatResponse
    case unexpectedPacketType
}

enum GS4PacketType: UInt8 {
    case handshake = 9
    case stat = 0
}

/// Parsed result of a GS4 full-stat query.
struct GS4FullStat: Equatable {
    var motd: String
    var gameType: String
    var mapName: String
    var numPlayers: Int
    var maxPlayers: Int
    var hostPort: Int
    var hostIP: String
    var players: [String]

    /// Everything else the server reports (plugins list, version, game_id, ...)
    /// that we don't model explicitly but keep around for display/debugging.
    var extraKeyValues: [String: String]
}

enum GS4Protocol {
    static let magic: [UInt8] = [0xFE, 0xFD]

    /// Builds the stage-1 handshake request. `sessionID` is echoed back
    /// by the server and should be masked to 0x0F0F0F0F per spec (top
    /// nibble of each byte must be zero) to stay compatible with all
    /// server implementations.
    static func handshakeRequest(sessionID: Int32) -> Data {
        var bytes = magic
        bytes.append(GS4PacketType.handshake.rawValue)
        bytes.append(contentsOf: sessionID.bigEndianBytes)
        return Data(bytes)
    }

    /// Parses the stage-1 handshake response, returning the numeric
    /// challenge token to embed in the full-stat request.
    static func parseHandshakeResponse(_ data: Data) throws -> Int32 {
        let bytes = [UInt8](data)
        // [type(1)][sessionID(4)][token string, null-terminated ASCII]
        guard bytes.count >= 6, bytes[0] == GS4PacketType.handshake.rawValue else {
            throw GS4Error.unexpectedPacketType
        }
        guard let nullIndex = bytes[5...].firstIndex(of: 0) else {
            throw GS4Error.malformedHandshakeResponse
        }
        let tokenString = String(decoding: bytes[5..<nullIndex], as: UTF8.self)
        guard let token = Int32(tokenString) else {
            throw GS4Error.malformedHandshakeResponse
        }
        return token
    }

    /// Builds the stage-2 full-stat request. The 4 trailing zero bytes
    /// (vs. omitting them) are what select "full" stat over "basic" stat.
    static func fullStatRequest(sessionID: Int32, token: Int32) -> Data {
        var bytes = magic
        bytes.append(GS4PacketType.stat.rawValue)
        bytes.append(contentsOf: sessionID.bigEndianBytes)
        bytes.append(contentsOf: token.bigEndianBytes)
        bytes.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // padding -> full stat
        return Data(bytes)
    }

    /// Parses the stage-2 full-stat response into a `GS4FullStat`.
    ///
    /// Wire layout after the leading type byte:
    ///   sessionID          4 bytes
    ///   padding            11 bytes  ("splitnum\0\x80\0")
    ///   K/V section        repeating <key>\0<value>\0 pairs, terminated
    ///                      by an extra \0
    ///   padding            10 bytes  ("\x01player_\0\0")
    ///   player list        repeating <name>\0, terminated by an extra \0
    static func parseFullStatResponse(_ data: Data) throws -> GS4FullStat {
        let bytes = [UInt8](data)
        guard bytes.count >= 5, bytes[0] == GS4PacketType.stat.rawValue else {
            throw GS4Error.unexpectedPacketType
        }

        var offset = 5 // skip type(1) + sessionID(4)
        offset += 11   // skip fixed "splitnum\0\x80\0" padding

        guard offset <= bytes.count else { throw GS4Error.malformedStatResponse }

        var kv: [String: String] = [:]
        while true {
            let key = try readCString(bytes, offset: &offset)
            if key.isEmpty { break } // double-null terminator of KV section
            let value = try readCString(bytes, offset: &offset)
            kv[key] = value
        }

        offset += 10 // skip fixed "\x01player_\0\0" padding ahead of player list
        guard offset <= bytes.count else { throw GS4Error.malformedStatResponse }

        var players: [String] = []
        while offset < bytes.count {
            let name = try readCString(bytes, offset: &offset)
            if name.isEmpty { break }
            players.append(name)
        }

        var kvCopy = kv
        let motd = kvCopy.removeValue(forKey: "hostname") ?? ""
        let gameType = kvCopy.removeValue(forKey: "gametype") ?? ""
        let mapName = kvCopy.removeValue(forKey: "map") ?? ""
        let numPlayers = Int(kvCopy.removeValue(forKey: "numplayers") ?? "") ?? players.count
        let maxPlayers = Int(kvCopy.removeValue(forKey: "maxplayers") ?? "") ?? 0
        let hostPort = Int(kvCopy.removeValue(forKey: "hostport") ?? "") ?? 0
        let hostIP = kvCopy.removeValue(forKey: "hostip") ?? ""

        return GS4FullStat(
            motd: motd,
            gameType: gameType,
            mapName: mapName,
            numPlayers: numPlayers,
            maxPlayers: maxPlayers,
            hostPort: hostPort,
            hostIP: hostIP,
            players: players,
            extraKeyValues: kvCopy
        )
    }

    /// Reads bytes up to (and past) the next 0x00 as a UTF-8 string.
    private static func readCString(_ bytes: [UInt8], offset: inout Int) throws -> String {
        guard let nullIndex = bytes[offset...].firstIndex(of: 0) else {
            throw GS4Error.malformedStatResponse
        }
        let string = String(decoding: bytes[offset..<nullIndex], as: UTF8.self)
        offset = nullIndex + 1
        return string
    }
}

extension Int32 {
    var bigEndianBytes: [UInt8] {
        let be = self.bigEndian
        return withUnsafeBytes(of: be, Array.init)
    }
}
