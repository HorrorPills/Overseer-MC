//
//  PlayerListParserTests.swift
//  OverseerTests
//

import Testing
@testable import Overseer

@Suite("PlayerListParser")
struct PlayerListParserTests {

    @Test("Parses a healthy /list response with multiple players")
    func parsesMultiplePlayers() throws {
        let response = "There are 2 of a max of 20 players online: Alice, Bob"
        #expect(try PlayerListParser.parse(response) == ["Alice", "Bob"])
    }

    @Test("Parses a single-player response")
    func parsesSinglePlayer() throws {
        let response = "There are 1 of a max of 20 players online: Alice"
        #expect(try PlayerListParser.parse(response) == ["Alice"])
    }

    @Test("Zero players online parses to an empty set, not an error")
    func parsesZeroPlayers() throws {
        #expect(try PlayerListParser.parse("There are 0 of a max of 20 players online: ").isEmpty)
        // Some server builds omit the trailing space entirely.
        #expect(try PlayerListParser.parse("There are 0 of a max of 20 players online:").isEmpty)
    }

    @Test("Tolerates irregular spacing around commas")
    func tolerantOfSpacing() throws {
        let response = "There are 3 of a max of 20 players online: Alice,Bob ,  Charlie"
        #expect(try PlayerListParser.parse(response) == ["Alice", "Bob", "Charlie"])
    }

    @Test("Throws on unrecognized output (e.g. RCON auth failure text)")
    func throwsOnUnrecognizedFormat() {
        #expect(throws: PlayerListParserError.unrecognizedFormat) {
            _ = try PlayerListParser.parse("Unknown command. Type \"/help\" for help.")
        }
    }
}
