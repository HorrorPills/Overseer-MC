//
//  PerfReportDiff.swift
//  Overseer
//
//  Compares two /perf reports' per-dimension entity/block-entity census
//  (an admin loads one from before a suspected incident and one from
//  after) — "12 fewer chests," "40 more creepers." Deliberately scoped
//  to the aggregate type counts only, which EntityCensusParser builds
//  from *every* row in entities.csv/block_entities.csv: those are
//  exhaustive per dimension, so a diff of them is trustworthy.
//
//  Chunk-level hotspots are NOT diffed here, on purpose — DimensionReport
//  only keeps each report's own top 15 by count (ChunkHotspotParser's
//  `limit`), so a chunk missing from one side might just have dropped
//  below the top 15, not actually lost anything. Diffing a truncated
//  list like that would look precise while quietly being wrong, which
//  is worse than not offering it.
//

import Foundation

struct CountDelta: Identifiable, Equatable {
    var type: String
    var before: Int
    var after: Int

    var id: String { type }
    var delta: Int { after - before }
}

struct DimensionDiff: Identifiable, Equatable {
    var name: String
    /// Sorted by |delta| descending; zero-delta types are dropped.
    var entityDeltas: [CountDelta]
    var blockEntityDeltas: [CountDelta]

    var id: String { name }
}

enum PerfReportDiff {
    static func diff(before: ParsedPerfReport, after: ParsedPerfReport) -> [DimensionDiff] {
        let beforeByName = Dictionary(before.dimensions.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let afterByName = Dictionary(after.dimensions.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let names = Set(beforeByName.keys).union(afterByName.keys).sorted()

        return names.map { name in
            DimensionDiff(
                name: name,
                entityDeltas: deltas(
                    before: beforeByName[name]?.entityCounts ?? [],
                    after: afterByName[name]?.entityCounts ?? []
                ),
                blockEntityDeltas: deltas(
                    before: beforeByName[name]?.blockEntityCounts ?? [],
                    after: afterByName[name]?.blockEntityCounts ?? []
                )
            )
        }
    }

    private static func deltas(before: [EntityTypeCount], after: [EntityTypeCount]) -> [CountDelta] {
        let beforeByType = Dictionary(before.map { ($0.type, $0.count) }, uniquingKeysWith: { first, _ in first })
        let afterByType = Dictionary(after.map { ($0.type, $0.count) }, uniquingKeysWith: { first, _ in first })
        let types = Set(beforeByType.keys).union(afterByType.keys)

        return types
            .map { CountDelta(type: $0, before: beforeByType[$0] ?? 0, after: afterByType[$0] ?? 0) }
            .filter { $0.delta != 0 }
            .sorted { abs($0.delta) == abs($1.delta) ? $0.type < $1.type : abs($0.delta) > abs($1.delta) }
    }
}
