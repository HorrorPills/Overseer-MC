//
//  PerfReportDiffTests.swift
//  OverseerTests
//

import Foundation
import Testing
@testable import Overseer

@Suite("PerfReportDiff")
struct PerfReportDiffTests {

    private func report(dimensions: [DimensionReport]) -> ParsedPerfReport {
        ParsedPerfReport(
            runSummary: PerfRunSummary(version: nil, timeSpanMs: nil, tickSpan: nil),
            systemInfo: [], tickStats: ServerTickStats(pendingTasks: nil, averageTickTimeMs: nil, tickTimesNanos: []),
            gamerules: [], serverProperties: [], topOffenders: [], dimensions: dimensions
        )
    }

    private func dimension(_ name: String, entities: [EntityTypeCount] = [], blockEntities: [EntityTypeCount] = []) -> DimensionReport {
        DimensionReport(
            name: name, entityCounts: entities, blockEntityCounts: blockEntities,
            entityHotspots: [], blockEntityHotspots: [], totalLoadedChunks: 0,
            totalBlockTicks: 0, totalFluidTicks: 0, levelStats: []
        )
    }

    @Test("Computes before/after/delta for a type present in both reports")
    func computesBasicDelta() {
        let before = report(dimensions: [dimension("overworld", blockEntities: [EntityTypeCount(type: "minecraft:chest", count: 12)])])
        let after = report(dimensions: [dimension("overworld", blockEntities: [EntityTypeCount(type: "minecraft:chest", count: 3)])])
        let diffs = PerfReportDiff.diff(before: before, after: after)
        let overworld = try! #require(diffs.first { $0.name == "overworld" })
        #expect(overworld.blockEntityDeltas == [CountDelta(type: "minecraft:chest", before: 12, after: 3)])
        #expect(overworld.blockEntityDeltas.first?.delta == -9)
    }

    @Test("A type present only in the 'after' report shows a before count of 0")
    func typeOnlyInAfterShowsZeroBefore() {
        let before = report(dimensions: [dimension("overworld")])
        let after = report(dimensions: [dimension("overworld", entities: [EntityTypeCount(type: "minecraft:creeper", count: 40)])])
        let diffs = PerfReportDiff.diff(before: before, after: after)
        let delta = try! #require(diffs.first { $0.name == "overworld" }?.entityDeltas.first)
        #expect(delta.before == 0)
        #expect(delta.after == 40)
        #expect(delta.delta == 40)
    }

    @Test("A type present only in the 'before' report shows an after count of 0 (it vanished)")
    func typeOnlyInBeforeShowsZeroAfter() {
        let before = report(dimensions: [dimension("overworld", blockEntities: [EntityTypeCount(type: "minecraft:shulker_box", count: 5)])])
        let after = report(dimensions: [dimension("overworld")])
        let diffs = PerfReportDiff.diff(before: before, after: after)
        let delta = try! #require(diffs.first { $0.name == "overworld" }?.blockEntityDeltas.first)
        #expect(delta.before == 5)
        #expect(delta.after == 0)
        #expect(delta.delta == -5)
    }

    @Test("Unchanged counts are excluded from the delta list")
    func unchangedCountsAreExcluded() {
        let before = report(dimensions: [dimension("overworld", entities: [EntityTypeCount(type: "minecraft:cow", count: 10)])])
        let after = report(dimensions: [dimension("overworld", entities: [EntityTypeCount(type: "minecraft:cow", count: 10)])])
        let diffs = PerfReportDiff.diff(before: before, after: after)
        #expect(diffs.first { $0.name == "overworld" }?.entityDeltas.isEmpty == true)
    }

    @Test("Results are sorted by absolute delta magnitude, descending")
    func sortsByAbsoluteMagnitude() {
        let before = report(dimensions: [dimension("overworld", entities: [
            EntityTypeCount(type: "minecraft:zombie", count: 10),
            EntityTypeCount(type: "minecraft:cow", count: 10)
        ])])
        let after = report(dimensions: [dimension("overworld", entities: [
            EntityTypeCount(type: "minecraft:zombie", count: 12), // delta +2
            EntityTypeCount(type: "minecraft:cow", count: 1)      // delta -9
        ])])
        let diffs = PerfReportDiff.diff(before: before, after: after)
        let types = diffs.first { $0.name == "overworld" }?.entityDeltas.map(\.type)
        #expect(types == ["minecraft:cow", "minecraft:zombie"])
    }

    @Test("A dimension present in only one report is still included, diffed against nothing")
    func dimensionOnlyInOneReportIsIncluded() {
        let before = report(dimensions: [])
        let after = report(dimensions: [dimension("the_end", entities: [EntityTypeCount(type: "minecraft:enderman", count: 3)])])
        let diffs = PerfReportDiff.diff(before: before, after: after)
        #expect(diffs.map(\.name) == ["the_end"])
        #expect(diffs[0].entityDeltas.first?.after == 3)
    }
}
