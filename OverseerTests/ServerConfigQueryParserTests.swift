//
//  ServerConfigQueryParserTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("ServerConfigQueryParser")
struct ServerConfigQueryParserTests {

    @Test("Parses a boolean gamerule query response")
    func parsesBooleanTrue() {
        #expect(ServerConfigQueryParser.parseBoolean("Gamerule mobGriefing is currently set to: true") == true)
    }

    @Test("Parses a false boolean gamerule query response")
    func parsesBooleanFalse() {
        #expect(ServerConfigQueryParser.parseBoolean("Gamerule keepInventory is currently set to: false") == false)
    }

    @Test("Boolean parsing is case-insensitive and tolerant of surrounding wording")
    func parsesBooleanTolerantly() {
        #expect(ServerConfigQueryParser.parseBoolean("keepInventory = TRUE") == true)
        #expect(ServerConfigQueryParser.parseBoolean("The gamerule doFireTick is False") == false)
    }

    @Test("Boolean parsing returns nil for an unrecognized response")
    func parsesBooleanNilOnGarbage() {
        #expect(ServerConfigQueryParser.parseBoolean("Unknown gamerule") == nil)
        #expect(ServerConfigQueryParser.parseBoolean("") == nil)
    }

    @Test("Parses a difficulty query response regardless of exact wording")
    func parsesDifficulty() {
        #expect(ServerConfigQueryParser.parseDifficulty("The difficulty is Normal") == "Normal")
        #expect(ServerConfigQueryParser.parseDifficulty("Difficulty: hard") == "Hard")
        #expect(ServerConfigQueryParser.parseDifficulty("peaceful") == "Peaceful")
    }

    @Test("Difficulty parsing returns nil for an unrecognized response")
    func parsesDifficultyNilOnGarbage() {
        #expect(ServerConfigQueryParser.parseDifficulty("no such rule") == nil)
    }
}
