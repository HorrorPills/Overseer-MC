//
//  PlayerRosterSync.swift
//  Overseer
//
//  Applies a fresh "who's online" roster to Player/PlayerSession,
//  regardless of which source produced it. Factored out of
//  PollingCoordinator (GS4/SLP) so RCONAutomationCoordinator's `/list`
//  poll can feed the exact same session-boundary rule described in
//  PlayerSession.swift instead of duplicating (and risking drifting
//  from) it.
//
//  Both callers run on @MainActor, so concurrent calls from the GS4
//  loop and the RCON `/list` loop are serialized by the actor, never
//  racing on `modelContext`.
//

import Foundation
import SwiftData

@MainActor
enum PlayerRosterSync {

    /// Usernames that opened/closed a session on this call, so a caller
    /// (RCONAutomationCoordinator) can surface "X joined/left the game"
    /// without re-deriving it from SessionDiffer itself.
    struct Result: Equatable {
        var joined: [String] = []
        var left: [String] = []
    }

    @discardableResult
    static func apply(
        onlineNames: Set<String>,
        at timestamp: Date,
        modelContext: ModelContext,
        automation: RCONAutomationCoordinator?
    ) -> Result {
        let activeDescriptor = FetchDescriptor<PlayerSession>(predicate: #Predicate { $0.endTime == nil })
        guard let activeSessions = try? modelContext.fetch(activeDescriptor) else { return Result() }

        let sessionsByUsername = Dictionary(
            activeSessions.compactMap { session -> (String, PlayerSession)? in
                guard let username = session.player?.username else { return nil }
                return (username, session)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let diff = SessionDiffer.diff(activeUsernames: Set(sessionsByUsername.keys), onlineNames: onlineNames)

        for username in diff.toBumpLastSeen {
            sessionsByUsername[username]?.player?.lastSeen = timestamp
        }

        for username in diff.toClose {
            guard let session = sessionsByUsername[username], let player = session.player else { continue }
            // Close at the player's last confirmed-present timestamp
            // (not "now"), so the session isn't over-counted by one
            // extra poll interval.
            let duration = session.close(at: player.lastSeen)
            player.playTimeSeconds += duration
            automation?.checkMilestones(for: player)
        }

        for username in diff.toOpen {
            let player = findOrCreatePlayer(named: username, at: timestamp, modelContext: modelContext)
            modelContext.insert(PlayerSession(player: player, startTime: timestamp))
            MojangAPI.shared.enrichIfNeeded(player: player)
        }

        try? modelContext.save()

        return Result(joined: diff.toOpen.sorted(), left: diff.toClose.sorted())
    }

    private static func findOrCreatePlayer(named username: String, at timestamp: Date, modelContext: ModelContext) -> Player {
        let descriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.username == username })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.lastSeen = timestamp
            return existing
        }
        let player = Player(username: username, firstSeen: timestamp, lastSeen: timestamp)
        modelContext.insert(player)
        return player
    }
}
