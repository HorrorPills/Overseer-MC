//
//  ServerListPing.swift
//  Overseer
//
//  Modern (post-1.7) Server List Ping protocol, TCP, VarInt-framed.
//  Reference: https://wiki.vg/Server_List_Ping
//
//  Handshake -> Status Request -> Status Response (JSON) -> Ping ->
//  Pong. We use the Ping/Pong round trip to measure `pingMs`, and the
//  Status Response JSON for MOTD/favicon/sample players/version as a
//  cross-check against (and fallback for) the GS4 query.
//
//  All packet building / JSON decoding here is pure (no networking), so
//  it is directly unit-testable against synthetic byte buffers.
//

import Foundation

enum SLPError: Error, Equatable {
    case malformedPacket
    case malformedJSON
    case pongPayloadMismatch
}

/// Status Response JSON payload shape.
struct SLPStatus: Decodable, Equatable {
    struct Version: Decodable, Equatable {
        var name: String
        var protocolVersion: Int

        enum CodingKeys: String, CodingKey {
            case name
            case protocolVersion = "protocol"
        }
    }

    struct Players: Decodable, Equatable {
        struct Sample: Decodable, Equatable {
            var name: String
            var id: String
        }
        var max: Int
        var online: Int
        var sample: [Sample]?
    }

    /// The `description` field is a Minecraft chat component: either a
    /// bare string or `{"text": "..."}` (possibly with nested
    /// formatting/extra we don't need for display purposes here).
    enum Description: Decodable, Equatable {
        case plain(String)
        case component(text: String)

        init(from decoder: Decoder) throws {
            if let container = try? decoder.singleValueContainer(),
               let text = try? container.decode(String.self) {
                self = .plain(text)
                return
            }
            struct Component: Decodable { var text: String? }
            let component = try Component(from: decoder)
            self = .component(text: component.text ?? "")
        }

        var text: String {
            switch self {
            case .plain(let s): return s
            case .component(let t): return t
            }
        }
    }

    var version: Version
    var players: Players
    var description: Description
    var favicon: String?
}

enum ServerListPingProtocol {
    /// Builds the handshake packet (packet ID 0x00) requesting the
    /// "status" next-state, wrapped with its VarInt length prefix.
    static func handshakePacket(host: String, port: UInt16, protocolVersion: Int32 = -1) -> Data {
        var body: [UInt8] = []
        body += VarInt.encode(0x00) // packet ID
        body += VarInt.encode(protocolVersion) // -1 = "unspecified", accepted by all server versions for status
        body += VarInt.encodeString(host)
        body += UInt16(port).bigEndianBytes
        body += VarInt.encode(1) // next state: 1 = status
        return framed(body)
    }

    /// Builds the empty Status Request packet (packet ID 0x00).
    static func statusRequestPacket() -> Data {
        framed(VarInt.encode(0x00))
    }

    /// Builds a Ping packet (packet ID 0x01) carrying an 8-byte payload
    /// (typically the current time) that the server must echo back
    /// unmodified in its Pong.
    static func pingPacket(payload: Int64) -> Data {
        var body: [UInt8] = []
        body += VarInt.encode(0x01)
        body += payload.bigEndianBytes
        return framed(body)
    }

    /// Wraps a packet body with its VarInt length prefix.
    static func framed(_ body: [UInt8]) -> Data {
        Data(VarInt.encode(Int32(body.count)) + body)
    }

    /// Parses a fully-received, length-prefix-stripped Status Response
    /// packet body (i.e. `[packet ID][VarInt json length][json bytes]`)
    /// into `SLPStatus`.
    static func parseStatusResponse(_ packetBody: Data) throws -> SLPStatus {
        let bytes = [UInt8](packetBody)
        var offset = 0
        let packetID = try VarInt.decode(bytes, offset: &offset)
        guard packetID == 0x00 else { throw SLPError.malformedPacket }
        let json = try VarInt.decodeString(bytes, offset: &offset)
        guard let jsonData = json.data(using: .utf8) else { throw SLPError.malformedJSON }
        do {
            return try JSONDecoder().decode(SLPStatus.self, from: jsonData)
        } catch {
            throw SLPError.malformedJSON
        }
    }

    /// Parses a Pong packet body and verifies its payload matches what
    /// we sent, returning nothing (throws on mismatch). Latency itself
    /// is measured by the caller (wall-clock delta around the
    /// send/receive), not derived from packet contents.
    static func validatePong(_ packetBody: Data, expectedPayload: Int64) throws {
        let bytes = [UInt8](packetBody)
        var offset = 0
        let packetID = try VarInt.decode(bytes, offset: &offset)
        guard packetID == 0x01 else { throw SLPError.malformedPacket }
        guard bytes.count - offset >= 8 else { throw SLPError.malformedPacket }
        let payloadBytes = Array(bytes[offset..<offset + 8])
        let payload = payloadBytes.withUnsafeBytes { $0.load(as: Int64.self) }.bigEndian
        guard payload == expectedPayload else { throw SLPError.pongPayloadMismatch }
    }
}

extension UInt16 {
    var bigEndianBytes: [UInt8] {
        let be = self.bigEndian
        return withUnsafeBytes(of: be, Array.init)
    }
}

extension Int64 {
    var bigEndianBytes: [UInt8] {
        let be = self.bigEndian
        return withUnsafeBytes(of: be, Array.init)
    }
}
