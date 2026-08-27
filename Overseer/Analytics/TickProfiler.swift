//
//  TickProfiler.swift
//  Overseer
//
//  Parses vanilla's `/tick query` RCON response. Since Paper's /tps is
//  off-limits on a strictly-vanilla server, this is the only source of
//  server-side performance data (MSPT) — everything else (ping, player
//  count) only tells us about the network, not the tick loop itself.
//
//  Expected response shape (vanilla 1.20.2+):
//    "Target tick rate: 20.0-tps. Actual tick rate: 20.0-tps (50.0-mspt)."
//    "Target tick rate: 20.0-tps. Actual tick rate: *20.0-tps (48.2-mspt)."
//      (a leading '*' on the actual rate flags a frozen/sprinting
//      tick manager state; still parsed the same way.)
//
//  Pure and dependency-free so it's directly unit-testable.
//

import Foundation

enum TickProfilerError: Error, Equatable {
    case unrecognizedFormat
}

struct TickReading: Equatable {
    var targetTps: Double
    var actualTps: Double
    var mspt: Double
}

enum TickProfiler {
    /// Matches the two `NN.N` numbers before "-tps" and the one before
    /// "-mspt", tolerating the optional leading '*' vanilla prints when
    /// the tick rate is being actively overridden (`/tick rate`,
    /// `/tick sprint`, `/tick freeze`).
    private static let pattern = try! NSRegularExpression(
        pattern: #"Target tick rate:\s*([\d.]+)-tps\.\s*Actual tick rate:\s*\*?([\d.]+)-tps\s*\(([\d.]+)-mspt\)"#
    )

    /// Filters `samples` (already timestamp-sorted, as `@Query` returns
    /// them) to a chart time range. Tick samples are polled at a much
    /// lower cadence than GS4/SLP snapshots (minutes, not seconds), so
    /// unlike `AnalyticsEngine.downsample`, no further bucketing is
    /// needed even at "All-Time" zoom.
    static func chartSamples(for range: AnalyticsEngine.TimeRange, samples: [TickSample], now: Date = .now) -> [TickSample] {
        guard let start = range.startDate(relativeTo: now) else { return samples }
        return samples.filter { $0.timestamp >= start }
    }

    static func parse(_ response: String) throws -> TickReading {
        let range = NSRange(response.startIndex..<response.endIndex, in: response)
        guard let match = pattern.firstMatch(in: response, range: range),
              let targetRange = Range(match.range(at: 1), in: response),
              let actualRange = Range(match.range(at: 2), in: response),
              let msptRange = Range(match.range(at: 3), in: response),
              let target = Double(response[targetRange]),
              let actual = Double(response[actualRange]),
              let mspt = Double(response[msptRange])
        else {
            throw TickProfilerError.unrecognizedFormat
        }
        return TickReading(targetTps: target, actualTps: actual, mspt: mspt)
    }
}
