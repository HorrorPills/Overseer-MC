//
//  PlayerStatsFileParserTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("PlayerStatsFileParser")
struct PlayerStatsFileParserTests {

    private func json(_ string: String) -> Data { Data(string.utf8) }

    @Test("Parses the modern minecraft:play_time key (1.17+)")
    func parsesPlayTime() throws {
        let data = json("""
        {"stats":{"minecraft:custom":{"minecraft:play_time":72000,"minecraft:jump":10}},"DataVersion":3700}
        """)
        let parsed = try PlayerStatsFileParser.parse(uuid: "u1", data: data, fileURL: URL(fileURLWithPath: "/tmp/u1.json"))
        #expect(parsed.playTimeTicks == 72000)
        #expect(parsed.playTimeSeconds == 3600) // 72000 ticks / 20 = 3600s = 1 hour
    }

    @Test("Falls back to the legacy minecraft:play_one_minute key (1.13–1.16)")
    func parsesLegacyKey() throws {
        let data = json("""
        {"stats":{"minecraft:custom":{"minecraft:play_one_minute":1200}}}
        """)
        let parsed = try PlayerStatsFileParser.parse(uuid: "u1", data: data, fileURL: URL(fileURLWithPath: "/tmp/u1.json"))
        #expect(parsed.playTimeTicks == 1200)
        #expect(parsed.playTimeSeconds == 60)
    }

    @Test("Prefers play_time over play_one_minute when both are somehow present")
    func prefersModernKey() throws {
        let data = json("""
        {"stats":{"minecraft:custom":{"minecraft:play_time":100,"minecraft:play_one_minute":999}}}
        """)
        let parsed = try PlayerStatsFileParser.parse(uuid: "u1", data: data, fileURL: URL(fileURLWithPath: "/tmp/u1.json"))
        #expect(parsed.playTimeTicks == 100)
    }

    @Test("Missing play-time stat parses with nil rather than throwing")
    func missingStatIsNilNotError() throws {
        let data = json("""
        {"stats":{"minecraft:custom":{"minecraft:jump":5}}}
        """)
        let parsed = try PlayerStatsFileParser.parse(uuid: "u1", data: data, fileURL: URL(fileURLWithPath: "/tmp/u1.json"))
        #expect(parsed.playTimeTicks == nil)
        #expect(parsed.playTimeSeconds == nil)
    }

    @Test("Throws on non-JSON or missing stats key")
    func throwsOnInvalidDocument() {
        #expect(throws: PlayerStatsFileParserError.self) {
            try PlayerStatsFileParser.parse(uuid: "u", data: json("not json"), fileURL: URL(fileURLWithPath: "/tmp/x.json"))
        }
        #expect(throws: PlayerStatsFileParserError.self) {
            try PlayerStatsFileParser.parse(uuid: "u", data: json("{\"DataVersion\":1}"), fileURL: URL(fileURLWithPath: "/tmp/x.json"))
        }
    }
}
