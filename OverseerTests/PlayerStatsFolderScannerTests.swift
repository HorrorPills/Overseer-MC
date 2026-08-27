//
//  PlayerStatsFolderScannerTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("PlayerStatsFolderScanner")
struct PlayerStatsFolderScannerTests {

    @Test("Only .json files are treated as stats files")
    func filtersByExtension() {
        #expect(PlayerStatsFolderScanner.isStatsFile(URL(fileURLWithPath: "/x/069a79f4-44e9-4726-a5be-fca90e38aaf5.json")))
        #expect(!PlayerStatsFolderScanner.isStatsFile(URL(fileURLWithPath: "/x/069a79f4-44e9-4726-a5be-fca90e38aaf5.json.bak")))
    }

    @Test("Valid entries parse into stats; malformed entries fall into failures without stopping the batch")
    func partitionsSuccessesAndFailures() {
        let good = Data("""
        {"stats":{"minecraft:custom":{"minecraft:play_time":200}}}
        """.utf8)
        let entries = [
            PlayerStatsScanEntry(uuid: "good-1", data: good, fileURL: URL(fileURLWithPath: "/x/good-1.json")),
            PlayerStatsScanEntry(uuid: "bad-1", data: Data("nope".utf8), fileURL: URL(fileURLWithPath: "/x/bad-1.json"))
        ]
        let result = PlayerStatsFolderScanner.scan(entries: entries)
        #expect(result.stats.count == 1)
        #expect(result.stats[0].uuid == "good-1")
        #expect(result.stats[0].playTimeTicks == 200)
        #expect(result.failures.count == 1)
        #expect(result.failures[0].uuid == "bad-1")
    }

    @Test("Empty entry list scans to empty results, not an error")
    func emptyEntriesScanCleanly() {
        let result = PlayerStatsFolderScanner.scan(entries: [])
        #expect(result.stats.isEmpty)
        #expect(result.failures.isEmpty)
    }
}
