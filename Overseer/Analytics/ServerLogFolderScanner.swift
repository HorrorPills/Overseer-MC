//
//  ServerLogFolderScanner.swift
//  Overseer
//
//  Batch counterpart to ServerLogJoinParser, same split as
//  PlayerStatsFolderScanner/PlayerDataFolderScanner: takes already-read
//  bytes so it stays a pure, unit-testable function, while LocationView
//  owns the actual directory enumeration and security-scoped file access.
//
//  Handles both plain `.log` files and gzip-rotated `.log.gz` ones
//  (reusing Gzip.swift, already relied on elsewhere for .schem files) —
//  a real log folder is mostly `.log.gz`, with only the current day as
//  plain-text `latest.log`.
//

import Foundation

struct LogFileEntry {
    var filename: String
    var data: Data
}

enum ServerLogFolderScanner {
    static func isLogFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".log") || name.hasSuffix(".log.gz")
    }

    /// `today` anchors `latest.log`'s dateless HH:MM:SS lines — pass a
    /// fixed value in tests, defaults to the moment the import runs.
    static func scan(entries: [LogFileEntry], today: Date = .now) -> [LogJoinRecord] {
        var records: [LogJoinRecord] = []
        for entry in entries {
            guard let text = decodedText(for: entry) else { continue }
            let isLatest = entry.filename.lowercased() == "latest.log"
            let day = isLatest ? today : (ServerLogJoinParser.inferredDate(fromFilename: entry.filename) ?? today)
            records.append(contentsOf: ServerLogJoinParser.parseJoins(from: text, day: day))
        }
        return records
    }

    private static func decodedText(for entry: LogFileEntry) -> String? {
        let raw: Data
        if entry.filename.lowercased().hasSuffix(".gz") {
            guard let decompressed = try? Gzip.decompress(entry.data) else { return nil }
            raw = decompressed
        } else {
            raw = entry.data
        }
        return String(data: raw, encoding: .utf8)
    }
}
