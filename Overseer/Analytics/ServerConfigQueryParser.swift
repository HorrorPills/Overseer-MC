//
//  ServerConfigQueryParser.swift
//  Overseer
//
//  Parses vanilla's `/gamerule <rule>` and `/difficulty` query
//  responses, used by the config drift watchdog (see
//  RCONAutomationCoordinator.checkConfigDrift) to detect someone
//  changing a gamerule or the difficulty out from under the admin —
//  e.g. `mobGriefing`/`keepInventory` flipped, which on a vanilla
//  survival server is as serious as a griefing incident itself.
//
//  Exact vanilla feedback wording (`commands.gamerule.query`,
//  `commands.difficulty.query`) isn't pinned down in either case —
//  intentionally tolerant, keyword-based extraction instead of a fixed
//  string match, the same defensive posture TickProfiler takes with the
//  optional leading '*' on `/tick query`.
//

import Foundation

enum ServerConfigQueryParser {
    private static let booleanPattern = try! NSRegularExpression(
        pattern: #"\b(true|false)\b"#,
        options: [.caseInsensitive]
    )

    /// Extracts a boolean gamerule's current value from its query
    /// response — the last true/false token in the string, since vanilla
    /// always states the rule name before the value ("Gamerule
    /// mobGriefing is currently set to: true").
    static func parseBoolean(_ response: String) -> Bool? {
        let range = NSRange(response.startIndex..<response.endIndex, in: response)
        let matches = booleanPattern.matches(in: response, range: range)
        guard let last = matches.last, let valueRange = Range(last.range(at: 1), in: response) else {
            return nil
        }
        return response[valueRange].lowercased() == "true"
    }

    private static let difficultyNames = ["peaceful", "easy", "normal", "hard"]

    /// Extracts the difficulty name from a `/difficulty` query response,
    /// case-insensitively, whatever the surrounding sentence wording.
    static func parseDifficulty(_ response: String) -> String? {
        let lower = response.lowercased()
        for name in difficultyNames where lower.contains(name) {
            return name.capitalized
        }
        return nil
    }
}
