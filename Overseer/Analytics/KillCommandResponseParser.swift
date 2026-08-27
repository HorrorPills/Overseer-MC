//
//  KillCommandResponseParser.swift
//  Overseer
//
//  Vanilla's `/kill` (with a target selector matching zero or more
//  entities) responds with free text like "Killed 42 entities" — this
//  pulls the count back out so the Entity Management view can show a
//  running summary instead of just firing commands into the void.
//

import Foundation

enum KillCommandResponseParser {
    /// Returns 0 (rather than throwing) for any response that doesn't
    /// contain a recognizable "Killed N" — a wording difference across
    /// versions should degrade the summary, not break the cleanup loop.
    static func parseKilledCount(_ response: String) -> Int {
        guard let range = response.range(of: "killed ", options: .caseInsensitive) else { return 0 }
        let digits = response[range.upperBound...].prefix(while: \.isNumber)
        return Int(digits) ?? 0
    }
}
