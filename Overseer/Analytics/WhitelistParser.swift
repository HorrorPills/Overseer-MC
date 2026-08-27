//
//  WhitelistParser.swift
//  Overseer
//
//  Parses vanilla's `/whitelist list` RCON response.
//
//  Expected response shape (vanilla, `commands.whitelist.list` /
//  `commands.whitelist.none`):
//    "There are 3 whitelisted players: Alice, Bob, Charlie"
//    "There are no whitelisted players"
//
//  Pure and dependency-free so it's directly unit-testable. Mirrors
//  PlayerListParser's approach but kept as its own file since the two
//  vanilla messages have a different shape (no "of a max of ...").
//

import Foundation

enum WhitelistParserError: Error, Equatable {
    case unrecognizedFormat
}

enum WhitelistParser {
    private static let pattern = try! NSRegularExpression(
        pattern: #"There are \d+ whitelisted players?:(.*)$"#,
        options: [.dotMatchesLineSeparators]
    )

    static func parse(_ response: String) throws -> Set<String> {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WhitelistParserError.unrecognizedFormat }
        if trimmed.localizedCaseInsensitiveContains("no whitelisted players") {
            return []
        }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = pattern.firstMatch(in: trimmed, range: range),
              let tailRange = Range(match.range(at: 1), in: trimmed)
        else {
            throw WhitelistParserError.unrecognizedFormat
        }
        let tail = trimmed[tailRange].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else { return [] }
        return Set(
            tail.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        )
    }
}
