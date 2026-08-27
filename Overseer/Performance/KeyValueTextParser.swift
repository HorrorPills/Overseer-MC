//
//  KeyValueTextParser.swift
//  Overseer
//
//  One parser for every "one setting per line" file a perf report
//  contains: system.txt and a level's stats.txt use "Key: Value" (colon
//  chosen as the split point, not ": ", since some system.txt lines —
//  e.g. an empty "Graphics card #0 name:" — have no space after the
//  colon at all); gamerules.txt and server.properties.txt use
//  "key=value". Both shapes reduce to "split on the first occurrence of
//  a separator character, trim both sides."
//

import Foundation

enum KeyValueTextParser {
    static func parse(_ text: String, separator: Character) -> [KeyValuePair] {
        // See SimpleCSV.rows for why `whereSeparator: \.isNewline` and
        // not `separator: "\n"` — a perf report mixes LF and CRLF
        // across its own files, so every parser here splits the same
        // defensive way rather than assuming one convention.
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("//"), let splitIndex = line.firstIndex(of: separator) else {
                return nil
            }
            let key = String(line[line.startIndex..<splitIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: splitIndex)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            return KeyValuePair(key: key, value: value)
        }
    }
}
