//
//  SimpleCSV.swift
//  Overseer
//
//  A bare comma-split, no quoting support. Every CSV a `/perf` report
//  writes (entities.csv, block_entities.csv, chunks.csv,
//  entity_chunks.csv) is vanilla's own straight `String.join(",", …)`
//  output — none of its columns (coordinates, UUIDs, namespaced IDs,
//  enums) ever contain a comma in practice, so a real RFC-4180 parser
//  would be solving a problem this data doesn't have. Columns are
//  looked up by header name rather than fixed position, so field
//  reordering in a future game version doesn't silently misread data.
//

import Foundation

enum SimpleCSV {
    static func rows(_ text: String) -> [[String]] {
        // `whereSeparator: \.isNewline` rather than `separator: "\n"` —
        // these files are written with CRLF line endings, and Swift's
        // `Character` treats "\r\n" as a single extended grapheme
        // cluster distinct from "\n" alone, so splitting on a bare "\n"
        // literal would never match and the whole file would come back
        // as one "row".
        text.split(whereSeparator: \.isNewline).map { line in
            line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
    }

    static func columnIndex(header: [String]) -> [String: Int] {
        Dictionary(header.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
