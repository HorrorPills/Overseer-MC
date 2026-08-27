//
//  Player.swift
//  Overseer
//
//  A known player identity, enriched asynchronously via MojangAPI.
//  `playTimeSeconds` is a cached rollup of all closed PlayerSession
//  durations; recompute it whenever a session closes (see
//  PollingCoordinator.closeSession(for:at:)) rather than summing on
//  every read.
//

import Foundation
import SwiftData

@Model
final class Player {
    /// In-game username. Treated as the natural primary key since GS4/SLP
    /// only ever report usernames (UUIDs require an extra Mojang lookup).
    @Attribute(.unique) var username: String

    /// Mojang UUID, resolved lazily by MojangAPI. Nil until enrichment runs.
    var uuid: String?

    /// First time this username was ever observed online.
    var firstSeen: Date

    /// Most recent time this username was observed online (updated every
    /// poll while they remain in the online list).
    var lastSeen: Date

    /// Cumulative playtime across all closed sessions, in seconds.
    var playTimeSeconds: Double

    /// Hour thresholds (see `MilestoneEvaluator.thresholdsHours`) this
    /// player has already been rewarded for, so a milestone is never
    /// announced/granted twice.
    var awardedMilestoneHours: [Int] = []

    /// Freeform admin notes ("known griefer," "trusted," "VIP," ...).
    /// Purely a local annotation — never sent anywhere, distinct from
    /// the in-game `admin` RCON tag (see VanillaCommands.tagAddAdmin).
    var notes: String = ""

    /// Griefing/theft triage state — see InvestigationStatus. Stored raw
    /// so it round-trips through SwiftData the same way ModerationEvent.Kind
    /// does; defaults every existing and new player to `.clear` until
    /// something actually flags them.
    private var investigationStatusRaw: String = InvestigationStatus.clear.rawValue

    var investigationStatus: InvestigationStatus {
        get { InvestigationStatus(rawValue: investigationStatusRaw) ?? .clear }
        set { investigationStatusRaw = newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \PlayerSession.player)
    var sessions: [PlayerSession] = []

    init(
        username: String,
        uuid: String? = nil,
        firstSeen: Date = .now,
        lastSeen: Date = .now,
        playTimeSeconds: Double = 0,
        awardedMilestoneHours: [Int] = [],
        notes: String = ""
    ) {
        self.username = username
        self.uuid = uuid
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.playTimeSeconds = playTimeSeconds
        self.awardedMilestoneHours = awardedMilestoneHours
        self.notes = notes
    }

    /// True if this player has an open (active, unclosed) session.
    var isOnline: Bool {
        sessions.contains { $0.endTime == nil }
    }
}
