//
//  WhitelistParserTests.swift
//  OverseerTests
//

import Testing
@testable import Overseer

@Suite("WhitelistParser")
struct WhitelistParserTests {

    @Test("Parses multiple whitelisted players")
    func parsesMultiplePlayers() throws {
        let response = "There are 3 whitelisted players: Alice, Bob, Charlie"
        #expect(try WhitelistParser.parse(response) == ["Alice", "Bob", "Charlie"])
    }

    @Test("Parses a single whitelisted player")
    func parsesSinglePlayer() throws {
        #expect(try WhitelistParser.parse("There are 1 whitelisted players: Alice") == ["Alice"])
    }

    @Test("Zero whitelisted players parses to an empty set, not an error")
    func parsesZeroPlayers() throws {
        #expect(try WhitelistParser.parse("There are no whitelisted players").isEmpty)
    }

    @Test("Throws on unrecognized output")
    func throwsOnUnrecognizedFormat() {
        #expect(throws: WhitelistParserError.unrecognizedFormat) {
            _ = try WhitelistParser.parse("Unknown command. Type \"/help\" for help.")
        }
    }
}
