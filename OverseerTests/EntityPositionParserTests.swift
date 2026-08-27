//
//  EntityPositionParserTests.swift
//  OverseerTests
//

import Testing
@testable import Overseer

@Suite("EntityPositionParser")
struct EntityPositionParserTests {

    @Test("Parses a standard /data get entity Pos response")
    func parsesStandardResponse() throws {
        let response = "Alice has the following entity data: [1234.5d, 65.0d, 5678.9d]"
        let position = try EntityPositionParser.parse(response)
        #expect(position.x == 1234.5)
        #expect(position.y == 65.0)
        #expect(position.z == 5678.9)
    }

    @Test("Parses negative coordinates")
    func parsesNegativeCoordinates() throws {
        let response = "Bob has the following entity data: [-102.34d, 71.0d, -998.1d]"
        let position = try EntityPositionParser.parse(response)
        #expect(position.x == -102.34)
        #expect(position.y == 71.0)
        #expect(position.z == -998.1)
    }

    @Test("Tolerates missing 'd' suffixes and irregular spacing")
    func tolerantOfFormatVariation() throws {
        let response = "Alice has the following entity data: [100,  64,-200]"
        let position = try EntityPositionParser.parse(response)
        #expect(position.x == 100)
        #expect(position.y == 64)
        #expect(position.z == -200)
    }

    @Test("Throws on unrecognized output")
    func throwsOnUnrecognizedFormat() {
        #expect(throws: EntityPositionParserError.unrecognizedFormat) {
            _ = try EntityPositionParser.parse("No entity was found")
        }
    }
}
