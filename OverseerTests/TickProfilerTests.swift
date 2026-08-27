//
//  TickProfilerTests.swift
//  OverseerTests
//

import Testing
import Foundation
@testable import Overseer

@Suite("TickProfiler")
struct TickProfilerTests {

    @Test("Parses a healthy /tick query response")
    func parsesHealthyResponse() throws {
        let response = "Target tick rate: 20.0-tps. Actual tick rate: 20.0-tps (50.0-mspt)"
        let reading = try TickProfiler.parse(response)
        #expect(reading.targetTps == 20.0)
        #expect(reading.actualTps == 20.0)
        #expect(reading.mspt == 50.0)
    }

    @Test("Parses a lagging response with fractional values")
    func parsesLaggingResponse() throws {
        let response = "Target tick rate: 20.0-tps. Actual tick rate: 14.3-tps (69.9-mspt)"
        let reading = try TickProfiler.parse(response)
        #expect(reading.actualTps == 14.3)
        #expect(reading.mspt == 69.9)
    }

    @Test("Tolerates the '*' vanilla prints when /tick rate has been overridden")
    func parsesOverriddenRatePrefix() throws {
        let response = "Target tick rate: 10.0-tps. Actual tick rate: *10.0-tps (48.2-mspt)"
        let reading = try TickProfiler.parse(response)
        #expect(reading.targetTps == 10.0)
        #expect(reading.actualTps == 10.0)
        #expect(reading.mspt == 48.2)
    }

    @Test("Throws on unrecognized output (e.g. RCON auth failure text)")
    func throwsOnUnrecognizedFormat() {
        #expect(throws: TickProfilerError.unrecognizedFormat) {
            _ = try TickProfiler.parse("Unknown command. Type \"/help\" for help.")
        }
    }

    @Test("isLagging flags actual TPS meaningfully below target")
    func isLaggingFlag() {
        let healthy = TickSample(targetTps: 20, actualTps: 20, mspt: 50)
        let lagging = TickSample(targetTps: 20, actualTps: 15, mspt: 66)
        #expect(!healthy.isLagging)
        #expect(lagging.isLagging)
    }

    @Test("chartSamples filters to the selected time range")
    func chartSamplesFiltering() {
        let now = Date()
        let samples = [
            TickSample(timestamp: now.addingTimeInterval(-3600 * 24 * 40), targetTps: 20, actualTps: 20, mspt: 50),
            TickSample(timestamp: now.addingTimeInterval(-3600 * 2), targetTps: 20, actualTps: 20, mspt: 50)
        ]
        let last7Days = TickProfiler.chartSamples(for: .last7Days, samples: samples, now: now)
        #expect(last7Days.count == 1)
        let allTime = TickProfiler.chartSamples(for: .allTime, samples: samples, now: now)
        #expect(allTime.count == 2)
    }
}
