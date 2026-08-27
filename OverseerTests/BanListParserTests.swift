//
//  BanListParserTests.swift
//  OverseerTests
//

import Testing
@testable import Overseer

@Suite("BanListParser")
struct BanListParserTests {

    @Test("Parses a single ban entry")
    func parsesSingleEntry() throws {
        let response = "There are 1 total banned players:\nSteve was banned by Server: Griefing"
        let entries = try BanListParser.parse(response)
        #expect(entries == [BanEntry(username: "Steve", bannedBy: "Server", reason: "Griefing")])
    }

    @Test("Parses multiple ban entries")
    func parsesMultipleEntries() throws {
        let response = "There are 2 total banned players:\nSteve was banned by Server: Griefing\nAlex was banned by Admin: Banned by an operator."
        let entries = try BanListParser.parse(response)
        #expect(entries.count == 2)
        #expect(entries[0] == BanEntry(username: "Steve", bannedBy: "Server", reason: "Griefing"))
        #expect(entries[1] == BanEntry(username: "Alex", bannedBy: "Admin", reason: "Banned by an operator."))
    }

    @Test("Zero banned players parses to an empty array, not an error")
    func parsesZeroBans() throws {
        #expect(try BanListParser.parse("There are no banned players").isEmpty)
    }

    @Test("Throws on unrecognized output")
    func throwsOnUnrecognizedFormat() {
        #expect(throws: BanListParserError.unrecognizedFormat) {
            _ = try BanListParser.parse("Unknown command. Type \"/help\" for help.")
        }
        #expect(throws: BanListParserError.unrecognizedFormat) {
            _ = try BanListParser.parse("")
        }
    }
}
