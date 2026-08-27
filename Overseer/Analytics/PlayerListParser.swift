//
//  PlayerListParser.swift
//  Overseer
//
//  Parses vanilla's `/list` RCON response. This is the RCON-side roster
//  check: GS4/SLP (ServerQueryEngine) is the primary, higher-frequency
//  source of "who's online," but GS4 query is disabled on plenty of
//  servers (`enable-query=false` is vanilla's own server.properties
//  default) and SLP's player sample can be capped or omitted entirely.
//  `/list` needs nothing but RCON, which the app already requires for
//  moderation — so RCONAutomationCoordinator polls it independently and
//  feeds the same PlayerRosterSync pipeline GS4/SLP does.
//
//  Expected response shape (vanilla, `commands.list.players`):
//    "There are 2 of a max of 20 players online: Alice, Bob"
//    "There are 0 of a max of 20 players online: "
//      (zero players still prints the trailing "online: ", just with
//      nothing — and possibly no trailing space — after the colon.)
//
//  Pure and dependency-free so it's directly unit-testable.
//

import Foundation

enum PlayerListParserError: Error, Equatable {
    case unrecognizedFormat
}

enum PlayerListParser {
    /// Matches everything after "online:" up to end of string; the
    /// player names themselves are recovered by splitting that tail on
    /// ", " rather than by the regex, since usernames can't be assumed
    /// free of unusual characters.
    private static let pattern = try! NSRegularExpression(
        pattern: #"There are \d+ of a max of \d+ players online:(.*)$"#,
        options: [.dotMatchesLineSeparators]
    )

    static func parse(_ response: String) throws -> Set<String> {
        let range = NSRange(response.startIndex..<response.endIndex, in: response)
        guard let match = pattern.firstMatch(in: response, range: range),
              let tailRange = Range(match.range(at: 1), in: response)
        else {
            throw PlayerListParserError.unrecognizedFormat
        }
        let tail = response[tailRange].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else { return [] }
        return Set(
            tail.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        )
    }
}
