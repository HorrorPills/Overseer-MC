//
//  ServerStatsParserTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("ServerStatsParser")
struct ServerStatsParserTests {

    @Test("Parses pending_tasks, average_tick_time, and the bracketed tick_times list")
    func parsesAllThreeFields() {
        let text = """
        pending_tasks: 0
        average_tick_time: 56.072990
        tick_times: [44638101, 45941337, 48862429]
        """
        let stats = ServerStatsParser.parse(text)
        #expect(stats.pendingTasks == 0)
        #expect(stats.averageTickTimeMs == 56.072990)
        #expect(stats.tickTimesNanos == [44638101, 45941337, 48862429])
    }

    @Test("Converts nanoseconds to milliseconds")
    func convertsToMilliseconds() {
        let stats = ServerStatsParser.parse("tick_times: [50000000, 100000000]")
        #expect(stats.tickTimesMs == [50, 100])
    }

    @Test("An empty tick_times array parses to an empty list, not a crash")
    func emptyArrayParsesCleanly() {
        let stats = ServerStatsParser.parse("tick_times: []")
        #expect(stats.tickTimesNanos.isEmpty)
    }

    @Test("CRLF line endings parse the same as LF")
    func handlesCRLFLineEndings() {
        let stats = ServerStatsParser.parse("pending_tasks: 3\r\naverage_tick_time: 10.5\r\n")
        #expect(stats.pendingTasks == 3)
        #expect(stats.averageTickTimeMs == 10.5)
    }

    @Test("Missing fields default to nil/empty rather than throwing")
    func missingFieldsDefaultCleanly() {
        let stats = ServerStatsParser.parse("")
        #expect(stats.pendingTasks == nil)
        #expect(stats.averageTickTimeMs == nil)
        #expect(stats.tickTimesNanos.isEmpty)
    }
}
