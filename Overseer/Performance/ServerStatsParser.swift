//
//  ServerStatsParser.swift
//  Overseer
//
//  server/stats.txt — three specific lines (pending_tasks,
//  average_tick_time, tick_times), the last of which is a bracketed,
//  comma-separated list of nanosecond tick durations rather than a
//  plain scalar, so it needs its own parse instead of
//  KeyValueTextParser's single-value-per-line assumption.
//

import Foundation

enum ServerStatsParser {
    static func parse(_ text: String) -> ServerTickStats {
        var pendingTasks: Int?
        var averageTickTimeMs: Double?
        var tickTimes: [Int64] = []

        // See SimpleCSV.rows for why `whereSeparator: \.isNewline`.
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = value(after: "pending_tasks:", in: line) {
                pendingTasks = Int(value)
            } else if let value = value(after: "average_tick_time:", in: line) {
                averageTickTimeMs = Double(value)
            } else if let value = value(after: "tick_times:", in: line) {
                let inner = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                guard !inner.isEmpty else { continue }
                tickTimes = inner.split(separator: ",").compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
            }
        }

        return ServerTickStats(pendingTasks: pendingTasks, averageTickTimeMs: averageTickTimeMs, tickTimesNanos: tickTimes)
    }

    private static func value(after prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }
}
