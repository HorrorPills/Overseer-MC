//
//  RunSummaryParserTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("RunSummaryParser")
struct RunSummaryParserTests {

    @Test("Parses version, time span, and tick span from the profiling.txt header")
    func parsesHeaderFields() {
        let text = """
        ---- Minecraft Profiler Results ----
        // Hello world

        Version: 26.3-snapshot-8
        Time span: 10054 ms
        Tick span: 76 ticks
        // This is approximately 7.56 ticks per second. It should be 20 ticks per second

        --- BEGIN PROFILE DUMP ---

        [00] tick(76/1) - 99.14%/99.14%
        --- END PROFILE DUMP ---
        """
        let summary = RunSummaryParser.parse(text)
        #expect(summary.version == "26.3-snapshot-8")
        #expect(summary.timeSpanMs == 10054)
        #expect(summary.tickSpan == 76)
    }

    @Test("approxTPS matches vanilla's own arithmetic")
    func computesApproxTPS() {
        let summary = PerfRunSummary(version: nil, timeSpanMs: 10054, tickSpan: 76)
        #expect(summary.approxTPS != nil)
        #expect(abs(summary.approxTPS! - 7.56) < 0.01)
    }

    @Test("approxTPS is nil when either component is missing")
    func approxTPSNilWhenIncomplete() {
        #expect(PerfRunSummary(version: nil, timeSpanMs: nil, tickSpan: 76).approxTPS == nil)
        #expect(PerfRunSummary(version: nil, timeSpanMs: 1000, tickSpan: nil).approxTPS == nil)
    }

    @Test("CRLF line endings parse the same as LF")
    func handlesCRLFLineEndings() {
        let summary = RunSummaryParser.parse("Version: 1.0\r\nTime span: 1000 ms\r\nTick span: 20 ticks\r\n")
        #expect(summary.version == "1.0")
        #expect(summary.timeSpanMs == 1000)
        #expect(summary.tickSpan == 20)
    }

    @Test("Stops scanning at the dump marker, ignoring anything that looks like a header line inside the tree")
    func stopsAtDumpMarker() {
        let text = """
        Version: 1.0
        --- BEGIN PROFILE DUMP ---
        Version: fake
        """
        let summary = RunSummaryParser.parse(text)
        #expect(summary.version == "1.0")
    }
}
