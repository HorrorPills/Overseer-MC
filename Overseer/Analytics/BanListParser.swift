//
//  BanListParser.swift
//  Overseer
//
//  Parses vanilla's `/banlist` RCON response.
//
//  Expected response shape (vanilla, `commands.banlist.list` /
//  `commands.banlist.entry`; over RCON, one command's feedback lines
//  are newline-joined into a single response, same as e.g. `/help`):
//    "There are 2 total banned players:
//     Steve was banned by Server: Griefing
//     Alex was banned by Admin: Banned by an operator."
//    "There are no banned players"
//
//  Pure and dependency-free so it's directly unit-testable.
//

import Foundation

enum BanListParserError: Error, Equatable {
    case unrecognizedFormat
}

struct BanEntry: Identifiable, Equatable {
    var id: String { username }
    var username: String
    var bannedBy: String
    var reason: String
}

enum BanListParser {
    private static let entryPattern = try! NSRegularExpression(
        pattern: #"^(\S+) was banned by (.+?):\s*(.*)$"#
    )

    static func parse(_ response: String) throws -> [BanEntry] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BanListParserError.unrecognizedFormat }
        if trimmed.localizedCaseInsensitiveContains("no banned players") {
            return []
        }

        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let header = lines.first, header.localizedCaseInsensitiveContains("banned players") else {
            throw BanListParserError.unrecognizedFormat
        }

        var entries: [BanEntry] = []
        for line in lines.dropFirst() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = entryPattern.firstMatch(in: line, range: range),
                  let nameRange = Range(match.range(at: 1), in: line),
                  let sourceRange = Range(match.range(at: 2), in: line),
                  let reasonRange = Range(match.range(at: 3), in: line)
            else {
                continue // a line we don't recognize shouldn't blow up the whole parse
            }
            entries.append(BanEntry(
                username: String(line[nameRange]),
                bannedBy: String(line[sourceRange]),
                reason: String(line[reasonRange])
            ))
        }
        return entries
    }
}
