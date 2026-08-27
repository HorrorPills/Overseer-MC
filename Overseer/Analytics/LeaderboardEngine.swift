//
//  LeaderboardEngine.swift
//  Overseer
//
//  Pure, side-effect-free rankings over `[Player]` — no RCON, no
//  network, entirely derived from data PollingCoordinator/
//  PlayerRosterSync already collected. Mirrors PlayerStatsEngine's
//  approach of operating directly on SwiftData model instances (fine to
//  unit test by constructing Player/PlayerSession in memory, no
//  ModelContext required).
//

import Foundation

enum LeaderboardEngine {

    struct PlaytimeEntry: Identifiable {
        var id: String { player.username }
        var player: Player
        var totalPlaytimeSeconds: Double
    }

    struct SessionCountEntry: Identifiable {
        var id: String { player.username }
        var player: Player
        var sessionCount: Int
    }

    struct LongestSessionEntry: Identifiable {
        var id: String { player.username }
        var player: Player
        var longestSessionSeconds: Double
    }

    /// Players with zero recorded playtime are excluded rather than
    /// shown tied at the bottom — an empty leaderboard slot isn't
    /// interesting.
    static func topByPlaytime(_ players: [Player], limit: Int = 10) -> [PlaytimeEntry] {
        players
            .filter { $0.playTimeSeconds > 0 }
            .sorted { $0.playTimeSeconds > $1.playTimeSeconds }
            .prefix(limit)
            .map { PlaytimeEntry(player: $0, totalPlaytimeSeconds: $0.playTimeSeconds) }
    }

    static func topBySessionCount(_ players: [Player], limit: Int = 10) -> [SessionCountEntry] {
        players
            .filter { !$0.sessions.isEmpty }
            .sorted { $0.sessions.count > $1.sessions.count }
            .prefix(limit)
            .map { SessionCountEntry(player: $0, sessionCount: $0.sessions.count) }
    }

    /// Longest *closed* session — the currently-open session (if any)
    /// has no `durationSeconds` yet and is excluded, same as
    /// PlayerStatsEngine's average-session math.
    static func topByLongestSession(_ players: [Player], limit: Int = 10) -> [LongestSessionEntry] {
        players
            .compactMap { player -> LongestSessionEntry? in
                guard let longest = player.sessions.compactMap(\.durationSeconds).max() else { return nil }
                return LongestSessionEntry(player: player, longestSessionSeconds: longest)
            }
            .sorted { $0.longestSessionSeconds > $1.longestSessionSeconds }
            .prefix(limit)
            .map { $0 }
    }

    static func newestPlayers(_ players: [Player], limit: Int = 10) -> [Player] {
        players
            .sorted { $0.firstSeen > $1.firstSeen }
            .prefix(limit)
            .map { $0 }
    }
}
