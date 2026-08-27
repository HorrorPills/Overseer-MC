//
//  PerfReportModels.swift
//  Overseer
//
//  Plain data model for a parsed vanilla `/perf start` … `/perf stop`
//  report folder — see PerfReportParsers.swift and PerformanceView.swift
//  for how this gets filled in. Deliberately not SwiftData: a perf
//  report is a one-off snapshot the admin re-loads from disk each time,
//  not something the app tracks over time.
//

import Foundation

/// One `Key: Value` or `Key=Value` line from a plain text config/info
/// file (system.txt, gamerules.txt, server.properties.txt, a level's
/// stats.txt). Kept as an ordered array rather than a dictionary so the
/// UI can show it in the file's own order.
struct KeyValuePair: Identifiable, Equatable {
    var key: String
    var value: String
    var id: String { key }
}

/// A count of how many entities/block entities of one type exist,
/// e.g. ("minecraft:zombie", 80).
struct EntityTypeCount: Identifiable, Equatable {
    var type: String
    var count: Int
    var id: String { type }
}

/// A loaded chunk (or, for entity tracking, chunk *section* — hence the
/// optional `y`) ranked by some count column — "which 16×16 column has
/// the most block entities," "which chunk section has the most
/// entities" — so an admin can `/tp` straight to a lag hotspot.
struct ChunkHotspot: Identifiable, Equatable {
    var x: Int
    var y: Int?
    var z: Int
    var value: Int
    var id: String { "\(x),\(y.map(String.init) ?? "_"),\(z),\(value)" }
}

/// One line of the profiler's percentage tree (profiling.txt's main
/// dump), flattened out of its original nested/indented form.
/// `path` holds every ancestor's name, root first, so a leaf can be
/// shown with full context ("tick › levels › … › minecraft:zombie › ai").
struct ProfilerNode: Identifiable {
    let id = UUID()
    var depth: Int
    var name: String
    var path: [String]
    var hits: Int
    var samples: Int
    var selfPercent: Double
    var totalPercent: Double

    var breadcrumb: String { (path + [name]).joined(separator: " › ") }
}

struct PerfRunSummary: Equatable {
    var version: String?
    var timeSpanMs: Int?
    var tickSpan: Int?

    /// `tickSpan / (timeSpanMs / 1000)` — the same arithmetic vanilla's
    /// own profiler footer comment does ("This is approximately X ticks
    /// per second").
    var approxTPS: Double? {
        guard let timeSpanMs, timeSpanMs > 0, let tickSpan else { return nil }
        return Double(tickSpan) / (Double(timeSpanMs) / 1000)
    }
}

/// `server/stats.txt` — a rolling buffer of the most recent tick
/// durations (not necessarily the same span as the profiler run itself;
/// vanilla keeps its own fixed-size ring buffer of these independently).
struct ServerTickStats: Equatable {
    var pendingTasks: Int?
    /// Vanilla's own reported rolling average, straight from the file —
    /// shown alongside (not reconciled with) the average computed from
    /// `tickTimesMs` below, since the two aren't necessarily the same
    /// sample window.
    var averageTickTimeMs: Double?
    var tickTimesNanos: [Int64]

    var tickTimesMs: [Double] { tickTimesNanos.map { Double($0) / 1_000_000 } }
}

struct DimensionReport: Identifiable, Equatable {
    /// The folder name under `server/levels/minecraft/` — "overworld",
    /// "the_nether", "the_end", or a custom dimension's id.
    var name: String
    var entityCounts: [EntityTypeCount]
    var blockEntityCounts: [EntityTypeCount]
    /// Top chunk *sections* by live entity count (from entity_chunks.csv).
    var entityHotspots: [ChunkHotspot]
    /// Top chunk *columns* by block entity count (from chunks.csv).
    var blockEntityHotspots: [ChunkHotspot]
    var totalLoadedChunks: Int
    var totalBlockTicks: Int
    var totalFluidTicks: Int
    var levelStats: [KeyValuePair]

    var id: String { name }
    var totalEntities: Int { entityCounts.reduce(0) { $0 + $1.count } }
    var totalBlockEntities: Int { blockEntityCounts.reduce(0) { $0 + $1.count } }
}

struct ParsedPerfReport {
    var runSummary: PerfRunSummary
    var systemInfo: [KeyValuePair]
    var tickStats: ServerTickStats
    var gamerules: [KeyValuePair]
    var serverProperties: [KeyValuePair]
    /// Profiler tree nodes sorted by self-time (time spent in that node
    /// specifically, excluding children) descending — the actual "what
    /// is expensive" answer, as opposed to total% which mostly just
    /// reflects tree depth near the root.
    var topOffenders: [ProfilerNode]
    var dimensions: [DimensionReport]
}
