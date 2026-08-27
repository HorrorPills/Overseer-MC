//
//  RunSummaryParser.swift
//  Overseer
//
//  The handful of header lines at the top of server/profiling.txt,
//  before "--- BEGIN PROFILE DUMP ---":
//
//    Version: 26.3-snapshot-8
//    Time span: 10054 ms
//    Tick span: 76 ticks
//
//  Scanning stops at the dump marker rather than reading the whole
//  (potentially multi-thousand-line) file for three lines.
//

import Foundation

enum RunSummaryParser {
    static func parse(_ text: String) -> PerfRunSummary {
        var version: String?
        var timeSpanMs: Int?
        var tickSpan: Int?

        // See SimpleCSV.rows for why `whereSeparator: \.isNewline`.
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("--- BEGIN PROFILE DUMP") { break }
            if let value = value(after: "Version:", in: line) {
                version = value
            } else if let value = value(after: "Time span:", in: line) {
                timeSpanMs = Int(value.replacingOccurrences(of: "ms", with: "").trimmingCharacters(in: .whitespaces))
            } else if let value = value(after: "Tick span:", in: line) {
                tickSpan = Int(value.replacingOccurrences(of: "ticks", with: "").trimmingCharacters(in: .whitespaces))
            }
        }

        return PerfRunSummary(version: version, timeSpanMs: timeSpanMs, tickSpan: tickSpan)
    }

    private static func value(after prefix: String, in line: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }
}
