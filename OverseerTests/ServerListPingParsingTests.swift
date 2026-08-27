//
//  ServerListPingParsingTests.swift
//  OverseerTests
//

import Testing
import Foundation
@testable import Overseer

@Suite("Server List Ping parsing")
struct ServerListPingParsingTests {

    @Test("Handshake packet is VarInt-framed and carries host/port/next-state")
    func handshakePacketShape() throws {
        let packet = ServerListPingProtocol.handshakePacket(host: "203.0.113.10", port: 25604)
        let bytes = [UInt8](packet)
        var offset = 0
        let length = try VarInt.decode(bytes, offset: &offset)
        #expect(Int(length) == bytes.count - offset)

        let packetID = try VarInt.decode(bytes, offset: &offset)
        #expect(packetID == 0x00)
        _ = try VarInt.decode(bytes, offset: &offset) // protocol version
        let host = try VarInt.decodeString(bytes, offset: &offset)
        #expect(host == "203.0.113.10")
        let portBytes = bytes[offset..<offset + 2]
        let port = UInt16(portBytes[portBytes.startIndex]) << 8 | UInt16(portBytes[portBytes.startIndex + 1])
        #expect(port == 25604)
    }

    @Test("Parses a Status Response JSON payload")
    func parsesStatusResponse() throws {
        let json = """
        {
          "version": { "name": "1.21.1", "protocol": 767 },
          "players": { "max": 40, "online": 3, "sample": [{"name":"Alice","id":"00000000-0000-0000-0000-000000000001"}] },
          "description": { "text": "Example Server - example.com" },
          "favicon": "data:image/png;base64,AAAA"
        }
        """
        let body = ServerListPingProtocol.framed(
            VarInt.encode(0x00) + VarInt.encodeString(json)
        )
        // parseStatusResponse expects the length-prefix-stripped body.
        var offset = 0
        let outerLength = try VarInt.decode([UInt8](body), offset: &offset)
        let packetBody = body.subdata(in: (body.startIndex + offset)..<(body.startIndex + offset + Int(outerLength)))

        let status = try ServerListPingProtocol.parseStatusResponse(packetBody)
        #expect(status.version.name == "1.21.1")
        #expect(status.version.protocolVersion == 767)
        #expect(status.players.max == 40)
        #expect(status.players.online == 3)
        #expect(status.players.sample?.first?.name == "Alice")
        #expect(status.description.text == "Example Server - example.com")
        #expect(status.favicon?.hasPrefix("data:image/png;base64,") == true)
    }

    @Test("Description decodes whether it's a bare string or a component")
    func descriptionVariants() throws {
        func decode(_ descriptionJSON: String) throws -> SLPStatus.Description {
            let json = """
            {"version":{"name":"1.21.1","protocol":767},"players":{"max":40,"online":0},"description":\(descriptionJSON)}
            """
            return try JSONDecoder().decode(SLPStatus.self, from: Data(json.utf8)).description
        }
        #expect(try decode("\"Plain MOTD\"").text == "Plain MOTD")
        #expect(try decode("{\"text\":\"Component MOTD\"}").text == "Component MOTD")
    }

    @Test("Validates a matching Pong payload and rejects a mismatched one")
    func pongValidation() throws {
        let payload: Int64 = 1234567890
        let pongBytes = VarInt.encode(0x01) + payload.bigEndianBytes
        try ServerListPingProtocol.validatePong(Data(pongBytes), expectedPayload: payload)

        #expect(throws: SLPError.pongPayloadMismatch) {
            try ServerListPingProtocol.validatePong(Data(pongBytes), expectedPayload: payload + 1)
        }
    }

    @Test("Malformed status response (bad packet ID) throws")
    func malformedStatusResponseThrows() {
        let bytes = VarInt.encode(0x99) + VarInt.encodeString("{}")
        #expect(throws: SLPError.malformedPacket) {
            _ = try ServerListPingProtocol.parseStatusResponse(Data(bytes))
        }
    }
}
