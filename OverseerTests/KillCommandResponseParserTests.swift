//
//  KillCommandResponseParserTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("KillCommandResponseParser")
struct KillCommandResponseParserTests {

    @Test("Parses the plural form")
    func parsesPluralForm() {
        #expect(KillCommandResponseParser.parseKilledCount("Killed 42 entities") == 42)
    }

    @Test("Parses the singular form")
    func parsesSingularForm() {
        #expect(KillCommandResponseParser.parseKilledCount("Killed 1 entity") == 1)
    }

    @Test("Matches case-insensitively")
    func matchesCaseInsensitively() {
        #expect(KillCommandResponseParser.parseKilledCount("killed 7 entities") == 7)
        #expect(KillCommandResponseParser.parseKilledCount("KILLED 7 ENTITIES") == 7)
    }

    @Test("Zero matched entities parses to 0")
    func zeroMatchedParsesToZero() {
        #expect(KillCommandResponseParser.parseKilledCount("Killed 0 entities") == 0)
    }

    @Test("Unrecognized response text falls back to 0 rather than throwing")
    func unrecognizedResponseFallsBackToZero() {
        #expect(KillCommandResponseParser.parseKilledCount("") == 0)
        #expect(KillCommandResponseParser.parseKilledCount("No entity was found") == 0)
        #expect(KillCommandResponseParser.parseKilledCount("Unknown command") == 0)
    }
}
